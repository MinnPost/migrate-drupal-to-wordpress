# DRUPAL-TO-WORDPRESS CONVERSION SCRIPT

# Changelog

# 07.29.2010 - Updated by Scott Anderson / Room 34 Creative Services http://blog.room34.com/archives/4530
# 02.06.2009 - Updated by Mike Smullin http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/
# 05.15.2007 - Updated by D’Arcy Norman http://www.darcynorman.net/2007/05/15/how-to-migrate-from-drupal-5-to-wordpress-2/
# 05.19.2006 - Created by Dave Dash http://spindrop.us/2006/05/19/migrating-from-drupal-47-to-wordpress/

# This assumes that WordPress and Drupal are in separate databases, named 'wordpress' and 'drupal'.
# If your database names differ, adjust these accordingly.


# Section 1 - Reset

	# Empty previous content from WordPress database.
	TRUNCATE TABLE `minnpost.wordpress`.wp_comments;
	TRUNCATE TABLE `minnpost.wordpress`.wp_links;
	TRUNCATE TABLE `minnpost.wordpress`.wp_postmeta;
	TRUNCATE TABLE `minnpost.wordpress`.wp_posts;
	TRUNCATE TABLE `minnpost.wordpress`.wp_term_relationships;
	TRUNCATE TABLE `minnpost.wordpress`.wp_term_taxonomy;
	TRUNCATE TABLE `minnpost.wordpress`.wp_terms;
	TRUNCATE TABLE `minnpost.wordpress`.wp_termmeta;
	TRUNCATE TABLE `minnpost.wordpress`.wp_redirection_items;

	# If you're not bringing over multiple Drupal authors, comment out these lines and the other
	# author-related queries near the bottom of the script.
	# This assumes you're keeping the default admin user (user_id = 1) created during installation.
	DELETE FROM `minnpost.wordpress`.wp_users WHERE ID > 1;
	DELETE FROM `minnpost.wordpress`.wp_usermeta WHERE user_id > 1;

	# it is also worth clearing out the individual object maps from the salesforce plugin because ids for things change, and this could break mappings anyway
	TRUNCATE TABLE `minnpost.wordpress`.wp_object_sync_sf_object_map;

	# reset the deserialize value so it can start over with deserializing
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 1
		WHERE option_name = 'deserialize_metadata_last_post_checked'
	;

	# this is where we stop deleting data to start over



# Section 2 - Core Posts

	# Posts from Drupal stories
	# Keeps private posts hidden.
	# parameter: line 109 contains the Drupal content types that we want to migrate
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_modified, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			r.body `post_content`,
			n.title `post_title`,
			t.field_teaser_value `post_excerpt`,
			substring_index(a.dst, '/', -1) `post_name`,
			FROM_UNIXTIME(n.changed) `post_modified`,
			n.type `post_type`,
			IF(n.status = 1, 'publish', 'draft') `post_status`
		FROM `minnpost.drupal`.node n
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions r
			USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a
			ON a.src = CONCAT('node/', n.nid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
		# Add more Drupal content types below if applicable.
		WHERE n.type IN ('article', 'article_full', 'audio', 'newsletter', 'page', 'video', 'slideshow')
	;


	# Fix post type; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-17826
	# Add more Drupal content types below if applicable
	# parameter: line 118 contains content types from parameter in line 109 that should be imported as 'posts'
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_type = 'post'
		WHERE post_type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
	;


	## Get Raw HTML content from article_full posts
	# requires the Raw HTML plugin in WP to be enabled
	# wrap it in [raw][/raw]


	# create temporary table for raw html content
	CREATE TABLE `wp_posts_raw` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_raw` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
		PRIMARY KEY (`ID`)
	);


	# store raw values in temp table
	# 1/12/17: this was broken and had to rename the table in the join. unclear why it ever worked before though.
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts_raw
		(id, post_content_raw)
		SELECT a.nid, h.field_html_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_article_full a USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_html AS h USING(nid, vid)
			WHERE h.field_html_value IS NOT NULL
	;


	# append raw data to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_raw
		ON wp_posts.ID = wp_posts_raw.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, '[raw]', wp_posts_raw.post_content_raw, '[/raw]')
	;


	# get rid of that temporary raw table
	DROP TABLE wp_posts_raw;


	## Get audio URLs from audio posts
	# Use the Audio format, and the core WordPress handling for audio files
	# this is [audio mp3="source.mp3"]

	# create temporary table for audio content
	CREATE TABLE `wp_posts_audio` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_audio` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
		PRIMARY KEY (`ID`)
	);


	# store audio urls in temp table
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_posts_audio
		(id, post_content_audio)
		SELECT a.nid, CONCAT('https://www.minnpost.com/', f.filepath) `post_content_audio`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_audio a USING(nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_audio_file_fid = f.fid
	;


	# append audio file to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_audio
		ON wp_posts.ID = wp_posts_audio.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, '<p>[audio mp3="', wp_posts_audio.post_content_audio, '"]</p>')
	;


	# get rid of that temporary audio table
	DROP TABLE wp_posts_audio;


	## Get video URLs/embeds from video posts
	# Use the Video format, and the core WordPress handling for video display
	# if it is a local file, this uses [video src="video-source.mp4"]
	# can expand to [video width="600" height="480" mp4="source.mp4" ogv="source.ogv" webm="source.webm"]
	# if it is an embed, it uses [embed width="123" height="456"]http://www.youtube.com/watch?v=dQw4w9WgXcQ[/embed]
	# the embeds only work if they have been added to the whitelist
	# width/height are optional on all these


	# create temporary table for video content
	CREATE TABLE `wp_posts_video` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_video` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
		PRIMARY KEY (`ID`)
	);


	# store video urls for local files in temp table
	# for drupal 6, the only way we can do this is to encode FLV files as mp4 files separately, and make sure they 
	# exist at the matching url (whatever.flv needs to be there as whatever.mp4)
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_posts_video
		(id, post_content_video)
		SELECT v.nid, REPLACE(CONCAT('[video src="https://www.minnpost.com/', f.filepath, '"]'), '.flv', '.mp4') `post_content_video`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING(nid, vid)
			INNER JOIN `minnpost.drupal`.files AS f ON v.field_flash_file_fid = f.fid
	;

	# store video urls for embed videos in temp table
	# drupal 6 (at least our version) only does vimeo and youtube
	# these do take the vid into account

	# vimeo
	INSERT INTO `minnpost.wordpress`.wp_posts_video
		(id, post_content_video)
		SELECT v.nid, CONCAT('[embed]https://vimeo.com/', v.field_embedded_video_value, '[/embed]') `post_content_video`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_embedded_video v USING(nid, vid)
			WHERE v.field_embedded_video_provider = 'vimeo'
			GROUP BY v.nid, v.vid
	;

	# youtube
	INSERT INTO `minnpost.wordpress`.wp_posts_video
		(id, post_content_video)
		SELECT v.nid, CONCAT('[embed]https://www.youtube.com/watch?v=', v.field_embedded_video_value, '[/embed]') `post_content_video`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_embedded_video v USING(nid, vid)
			WHERE v.field_embedded_video_provider = 'youtube'
			GROUP BY v.nid, v.vid
	;


	# append video file or embed content to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_video
		ON wp_posts.ID = wp_posts_video.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, '<p>', wp_posts_video.post_content_video, '</p>')
	;


	# get rid of that temporary video table
	DROP TABLE wp_posts_video;


	## Get gallery images from slideshow posts
	# Use the Gallery format, and the core WordPress handling for image galleries
	# this is [gallery ids="729,732,731,720"]

	# create temporary table for gallery content
	CREATE TABLE `wp_posts_gallery` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_gallery` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
		PRIMARY KEY (`ID`)
	);


	# store gallery ids in temp table
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_posts_gallery
		(id, post_content_gallery)
		SELECT s.nid, GROUP_CONCAT(DISTINCT n.nid) `post_content_gallery`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			LEFT JOIN `minnpost.drupal`.content_field_op_slideshow_images sr ON sr.vid = n.vid
			LEFT JOIN `minnpost.drupal`.content_field_op_slideshow_images s ON s.field_op_slideshow_images_nid = n.nid
			WHERE s.nid IS NOT NULL
			GROUP BY s.nid
	;


	# append gallery to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_gallery
		ON wp_posts.ID = wp_posts_gallery.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, '<div id="image-gallery-slideshow">[gallery link="file" ids="', wp_posts_gallery.post_content_gallery, '"]</div>')
	;


	# get rid of that temporary gallery table
	DROP TABLE wp_posts_gallery;


	## Get Document Cloud urls from article posts
	# requires the Document Cloud plugin in WP to be enabled
	# uses the [documentcloud url="https://www.documentcloud.org/documents/282753-lefler-thesis.html"] shortcode


	# create temporary table for documentcloud content
	CREATE TABLE `wp_posts_documentcloud` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_documentcloud` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
		PRIMARY KEY (`ID`)
	);


	# store documentcloud data in temp table
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts_documentcloud
		(id, post_content_documentcloud)
		SELECT a.nid, CONCAT('<p><strong>DocumentCloud Document(s):</strong></p>', '[documentcloud url="', GROUP_CONCAT(d.field_op_documentcloud_doc_url SEPARATOR '"][documentcloud url="'), '"]') as urlsa
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_article a USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_documentcloud_doc d USING(nid, vid)
			WHERE d.field_op_documentcloud_doc_url IS NOT NULL
			GROUP BY nid, vid
	;


	# append documentcloud data to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_documentcloud
		ON wp_posts.ID = wp_posts_documentcloud.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, wp_posts_documentcloud.post_content_documentcloud)
	;


	# get rid of that temporary documentcloud table
	DROP TABLE wp_posts_documentcloud;


	# Fix images in post content; uncomment if you're moving files from "files" to "wp-content/uploads".
	# in our case, we use this to make the urls absolute, at least for now
	# no need for vid stuff
	#UPDATE `minnpost.wordpress`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"/wp-content/uploads/');
	UPDATE `minnpost.wordpress`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
	;


	# Miscellaneous clean-up.
	# There may be some extraneous blank spaces in your Drupal posts; use these queries
	# or other similar ones to strip out the undesirable tags.
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<p>&nbsp;</p>','')
	;
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<p class="italic">&nbsp;</p>','')
	;
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<p class="bold">&nbsp;</p>','')
	;

	# these items we don't currently use

	# Fix post_name to remove paths.
	# If applicable; Drupal allows paths (i.e. slashes) in the dst field, but this breaks
	# WordPress URLs. If you have mod_rewrite turned on, stripping out the portion before
	# the final slash will allow old site links to work properly, even if the path before
	# the slash is different!

	# this does not seem to be useful for us

	/*UPDATE `minnpost.wordpress`.wp_posts
		SET post_name =
		REVERSE(SUBSTRING(REVERSE(post_name),1,LOCATE('/',REVERSE(post_name))-1))
	;*/

	# NEW PAGES - READ BELOW AND COMMENT OUT IF NOT APPLICABLE TO YOUR SITE
	# MUST COME LAST IN THE SCRIPT AFTER ALL OTHER QUERIES!
	# If your site will contain new pages, you can set up the basic structure for them here.
	# Once the import is complete, go into the WordPress admin and copy content from the Drupal
	# pages (which are set to "pending" in a query above) into the appropriate new pages.
	#INSERT INTO `minnpost.wordpress`.wp_posts
	#	(`post_author`, `post_date`, `post_date_gmt`, `post_content`, `post_title`,
	#	`post_excerpt`, `post_status`, `comment_status`, `ping_status`, `post_password`,
	#	`post_name`, `to_ping`, `pinged`, `post_modified`, `post_modified_gmt`,
	#	`post_content_filtered`, `post_parent`, `guid`, `menu_order`, `post_type`,
	#	`post_mime_type`, `comment_count`)
	#	VALUES
	#	(1, NOW(), NOW(), 'Page content goes here, or leave this value empty.', 'Page Title',
	#	'', 'publish', 'closed', 'closed', '',
	#	'slug-goes-here', '', '', NOW(), NOW(),
	#	'', 0, 'http://full.url.to.page.goes.here', 1, 'page', '', 0)
	#;



# Section 3 - Core Post Metadata

	# core post text/wysiwyg/etc fields

	# get all kinds of post teasers if we have them
	# this one does take the vid into account
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.drupal`.node n ON wp_posts.ID = n.nid
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
		SET wp_posts.post_excerpt = t.field_teaser_value
		WHERE t.field_teaser_value != '' AND t.field_teaser_value != NULL
	;


	# deck field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				d.nid `post_id`,
				'_mp_subtitle_settings_deck' as meta_key,
				d.field_deck_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_deck d USING(nid, vid)
			WHERE d.field_deck_value IS NOT NULL
	;


	# byline field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				b.nid `post_id`,
				'_mp_subtitle_settings_byline' as meta_key,
				b.field_byline_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_byline b USING(nid, vid)
			WHERE b.field_byline_value IS NOT NULL
	;


	# newsletter fields

	# add a temporary constraint for newsletter type stuff so we don't add duplicates
	ALTER TABLE `minnpost.wordpress`.wp_postmeta ADD CONSTRAINT temp_newsletter_type UNIQUE (post_id, meta_key, meta_value(64));

	# type field - the data is easier if we just do this one separately for the three types
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_type' as meta_key, 'daily' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
			WHERE tn.tid = 219 and n.type = 'newsletter'
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_type' as meta_key, 'greater_mn' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
			WHERE tn.tid = 220 and n.type = 'newsletter'
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_type' as meta_key, 'book_club' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
			WHERE tn.tid = 221 and n.type = 'newsletter'
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_type' as meta_key, 'sunday_review' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
			WHERE tn.tid = 5396 and n.type = 'newsletter'
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_type' as meta_key, 'dc_memo' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
			WHERE tn.tid = 7910 and n.type = 'newsletter'
	;


	# newsletter preview text field
	# this one does take the vid into account
	# note: this field currently does not exist in any newsletters, so it will error unless someone uses it
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				p.nid `post_id`,
				'_mp_newsletter_preview_text' as meta_key,
				p.field_preview_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_preview_text p USING(nid, vid)
			WHERE p.field_preview_value IS NOT NULL
	;


	# add top stories for all newsletter posts
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_top_posts_csv' as meta_key, GROUP_CONCAT(t.field_newsletter_top_nid) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_newsletter_top t USING(nid, vid)
			WHERE t.field_newsletter_top_nid IS NOT NULL
			GROUP BY nid, vid
	;


	# add more stories for all newsletter posts
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_more_posts_csv' as meta_key, GROUP_CONCAT(m.field_newsletter_more_nid) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_newsletter_more m USING(nid, vid)
			WHERE m.field_newsletter_more_nid IS NOT NULL
			GROUP BY nid, vid
	;


	# drop that temporary constraint for newsletter type
	ALTER TABLE `minnpost.wordpress`.wp_postmeta DROP INDEX temp_newsletter_type;



# Section 4 - Tags, Post Formats, and their taxonomies and relationships to posts

	# Tags from Drupal vocabularies
	# Using REPLACE prevents script from breaking if Drupal contains duplicate terms.
	# permalinks are going to break for tags whatever we do, because drupal puts them all into folders (ie https://www.minnpost.com/category/social-tags/architect)
	# we have to determine which tags should instead be (or already are) categories, so we don't have permalinks like books-1
	REPLACE INTO `minnpost.wordpress`.wp_terms
		(term_id, `name`, slug, term_group)
		SELECT DISTINCT
			d.tid `term_id`,
			d.name `name`,
			substring_index(a.dst, '/', -1) `slug`,
			0 `term_group`
		FROM `minnpost.drupal`.term_data d
		INNER JOIN `minnpost.drupal`.term_hierarchy h
			USING(tid)
		INNER JOIN `minnpost.drupal`.term_node n
			USING(tid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a
			ON a.src = CONCAT('taxonomy/term/', d.tid)
		WHERE (1
		 	# This helps eliminate spam tags from import; uncomment if necessary.
		 	# AND LENGTH(d.name) < 50
		)
	;


	# Taxonomy for tags
	# creates a taxonomy item for each tag
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy
		(term_id, taxonomy, description, parent)
		SELECT DISTINCT
			d.tid `term_id`,
			'post_tag' `taxonomy`,
			d.description `description`,
			h.parent `parent`
		FROM `minnpost.drupal`.term_data d
		INNER JOIN `minnpost.drupal`.term_hierarchy h
			USING(tid)
	;


	# add audio format for audio posts
	INSERT INTO `minnpost.wordpress`.wp_terms (name, slug) VALUES ('post-format-audio', 'post-format-audio');


	# add format to taxonomy
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
		SELECT term_id `term_id`, 'post_format' `taxonomy`
			FROM wp_terms
			WHERE `minnpost.wordpress`.wp_terms.name = 'post-format-audio'
	;


	# use audio format for audio posts
	# this doesn't really seem to need any vid stuff
	INSERT INTO wp_term_relationships (object_id, term_taxonomy_id)
		SELECT n.nid, tax.term_taxonomy_id
			FROM `minnpost.drupal`.node n
			CROSS JOIN `minnpost.wordpress`.wp_term_taxonomy tax
			LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
			WHERE `minnpost.drupal`.n.type = 'audio' AND tax.taxonomy = 'post_format' AND t.name = 'post-format-audio'
	;


	# add video format for video posts
	INSERT INTO `minnpost.wordpress`.wp_terms (name, slug) VALUES ('post-format-video', 'post-format-video');


	# add format to taxonomy
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
		SELECT term_id `term_id`, 'post_format' `taxonomy`
			FROM wp_terms
			WHERE `minnpost.wordpress`.wp_terms.name = 'post-format-video'
	;


	# use video format for video posts
	# this doesn't really seem to need any vid stuff
	INSERT INTO wp_term_relationships (object_id, term_taxonomy_id)
		SELECT n.nid, tax.term_taxonomy_id
			FROM `minnpost.drupal`.node n
			CROSS JOIN `minnpost.wordpress`.wp_term_taxonomy tax
			LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
			WHERE `minnpost.drupal`.n.type = 'video' AND tax.taxonomy = 'post_format' AND t.name = 'post-format-video'
	;


	# add gallery format for gallery posts
	INSERT INTO `minnpost.wordpress`.wp_terms (name, slug) VALUES ('post-format-gallery', 'post-format-gallery');


	# add format to taxonomy
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
		SELECT term_id `term_id`, 'post_format' `taxonomy`
			FROM wp_terms
			WHERE `minnpost.wordpress`.wp_terms.name = 'post-format-gallery'
	;


	# use gallery format for gallery posts
	# this doesn't really seem to need any vid stuff
	INSERT INTO wp_term_relationships (object_id, term_taxonomy_id)
		SELECT n.nid, tax.term_taxonomy_id
			FROM `minnpost.drupal`.node n
			CROSS JOIN `minnpost.wordpress`.wp_term_taxonomy tax
			LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
			WHERE `minnpost.drupal`.n.type = 'slideshow' AND tax.taxonomy = 'post_format' AND t.name = 'post-format-gallery'
	;


	# Post/Tag relationships

	# Temporary table for post relationships with tags
	CREATE TABLE `wp_term_relationships_posts` (
		`object_id` bigint(20) unsigned NOT NULL DEFAULT '0',
		`term_taxonomy_id` bigint(20) unsigned NOT NULL DEFAULT '0',
		`term_order` int(11) NOT NULL DEFAULT '0',
		PRIMARY KEY (`object_id`,`term_taxonomy_id`),
		KEY `term_taxonomy_id` (`term_taxonomy_id`)
	);


	# store with the term_id from drupal
	# this will break if we incorporate the vid. maybe because drupal stores terms with no nodes, so we can't start with the node table
	INSERT INTO `minnpost.wordpress`.wp_term_relationships_posts (object_id, term_taxonomy_id)
		SELECT DISTINCT nid, tid FROM `minnpost.drupal`.term_node
	;


	# get the term_taxonomy_id for each term and put it in the table
	# needs an ignore because there's at least one duplicate now
	UPDATE IGNORE `minnpost.wordpress`.wp_term_relationships_posts r
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_id
		SET r.term_taxonomy_id = tax.term_taxonomy_id
	;


	# put the post/tag relationships into the correct table
	INSERT INTO `minnpost.wordpress`.wp_term_relationships (object_id, term_taxonomy_id)
		SELECT object_id, term_taxonomy_id FROM wp_term_relationships_posts p
	;


	# Update tag counts.
	UPDATE wp_term_taxonomy tt
		SET `count` = (
			SELECT COUNT(tr.object_id)
			FROM wp_term_relationships tr
			WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
		)
	;


	# get rid of that temporary tag relationship table
	DROP TABLE wp_term_relationships_posts;


# Section 5 - Categories and Category Metadata


# CATEGORIES
# These are NEW categories, not in `minnpost.drupal`. Add as many sets as needed.
#INSERT IGNORE INTO `minnpost.wordpress`.wp_terms (name, slug)
#	VALUES
#	('First Category', 'first-category'),
#	('Second Category', 'second-category'),
#	('Third Category', 'third-category')
#;

# this category stuff by default breaks because the term ID has already been used - by the tag instead of the category
# it fails to add the duplicate IDs because Drupal has them in separate tables
# we fix this by temporarily using a term_id_old field to track the relationships


# add the term_id_old field for tracking Drupal term IDs
ALTER TABLE wp_terms ADD term_id_old BIGINT(20);


# Temporary table for department terms
CREATE TABLE `wp_terms_dept` (
	`term_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	`name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`slug` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`term_group` bigint(10) NOT NULL DEFAULT '0',
	PRIMARY KEY (`term_id`),
	KEY `slug` (`slug`(191)),
	KEY `name` (`name`(191))
);


# Put all Drupal departments into the temporary table
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_dept (term_id, name, slug)
	SELECT nid `term_id`,
	n.title `name`,
	substring_index(a.dst, '/', -1) `slug`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
		WHERE n.type='department'
;


# Put all Drupal departments into terms; store old term ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, term_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_dept d
;


# Create taxonomy for each department
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id, 'category' FROM wp_terms WHERE term_id_old IS NOT NULL
;


# Create relationships for each story to the departments it had in Drupal
# Track this relationship by the term_id_old field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT dept.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.nid = n.nid AND dept.vid = n.vid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			WHERE tax.taxonomy = 'category'
;


# text fields for categories

# excerpt field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_excerpt' as meta_key, t.field_teaser_value `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_teaser t ON t.nid = n.nid AND t.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'department' AND t.field_teaser_value IS NOT NULL
;


# sponsorship field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_sponsorship' as meta_key, s.field_sponsorship_value `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_sponsorship s ON s.nid = n.nid AND s.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'department' AND s.field_sponsorship_value IS NOT NULL
;


# body field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_body' as meta_key, nr.body `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'department' AND nr.body IS NOT NULL AND nr.body != ''
;


# thumbnail url
# this is the small thumbnail from cache folder
# this one does take the vid into account
# have verified that all these department file urls exist
INSERT IGNORE INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `term_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		REPLACE(CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/department', '/imagecache/thumbnail/images/thumbnails/department')), 'https://www.minnpost.com/sites/default/files/images/thumbnails', 'https://www.minnpost.com/sites/default/files/imagecache/thumbnail/images/thumbnails') `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
		WHERE n.type = 'department'
;


# main image url
# this is the main image from cache folder
# this one does take the vid into account
# have verified that all these department file urls exist
INSERT IGNORE INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `term_id`,
		'_category_main_image_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', f.filepath) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
		WHERE n.type = 'department'
;


# Empty term_id_old values so we can start over with our auto increment and still track for sections
UPDATE `minnpost.wordpress`.wp_terms SET term_id_old = NULL;


# get rid of that temporary department table
DROP TABLE wp_terms_dept;


# set the department as the primary category for the post, because that is how drupal handles urls
# in wordpress, this depends on the WP Category Permalink plugin
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT object_id as post_id, '_category_permalink' as meta_key, CONCAT('a:1:{s:8:"category";s:4:"', t.term_id, '";}') as meta_value
		FROM wp_term_relationships r
		INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
		INNER JOIN wp_terms t ON tax.term_id = t.term_id
		WHERE tax.taxonomy = 'category'
;


# Temporary table for section terms
CREATE TABLE `wp_terms_section` (
	`term_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	`name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`slug` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`term_group` bigint(10) NOT NULL DEFAULT '0',
	PRIMARY KEY (`term_id`),
	KEY `slug` (`slug`(191)),
	KEY `name` (`name`(191))
);


# Put all Drupal sections into the temporary table
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_section (term_id, name, slug)
	SELECT nid `term_id`,
	n.title `name`,
	substring_index(a.dst, '/', -1) `slug`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
		WHERE n.type='section'
;


# Put all Drupal sections into terms; store old term ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, term_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_section s
;


# Create taxonomy for each section
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id, 'category' FROM wp_terms WHERE term_id_old IS NOT NULL
;


# Create relationships for each story to the section it had in Drupal
# Track this relationship by the term_id_old field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT section.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
			INNER JOIN `minnpost.drupal`.node n ON section.nid = n.nid AND section.vid = n.vid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			WHERE tax.taxonomy = 'category'
;


# excerpt field
# this one does take the vid into account
# currently none of these have values even though the field is available to them
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_excerpt' as meta_key, t.field_teaser_value `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
			INNER JOIN `minnpost.drupal`.node n ON section.field_section_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_teaser t ON t.nid = n.nid AND t.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'section' AND t.field_teaser_value IS NOT NULL
;


# sponsorship field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_sponsorship' as meta_key, s.field_sponsorship_value `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
			INNER JOIN `minnpost.drupal`.node n ON section.field_section_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_sponsorship s ON s.nid = n.nid AND s.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'section' AND s.field_sponsorship_value IS NOT NULL
;


# body field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_termmeta
	(term_id, meta_key, meta_value)
	SELECT DISTINCT term.term_id as `term_id`, '_mp_category_body' as meta_key, nr.body `meta_value`
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
			INNER JOIN `minnpost.drupal`.node n ON section.field_section_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			WHERE tax.taxonomy = 'category' AND n.type = 'section' AND nr.body IS NOT NULL AND nr.body != ''
;


# sections have no images


# Empty term_id_old values so we can start over with our auto increment if applicable
UPDATE `minnpost.wordpress`.wp_terms SET term_id_old = NULL;


# get rid of that temporary section table
DROP TABLE wp_terms_section;


# get rid of that term_id_old field if we are done migrating into wp_terms
ALTER TABLE wp_terms DROP COLUMN term_id_old;


# Make categories that aren't in Drupal because permalinks break if the story doesn't have a category at all
INSERT INTO wp_terms (name, slug, term_group)
	VALUES
		('Galleries', 'galleries', 0)
;


# Create taxonomy for those new categories
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id, 'category'
	FROM wp_terms
	WHERE slug = 'galleries'
	ORDER BY term_id DESC
	LIMIT 1
;


# Create relationships for each gallery story to this new category
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT nid as object_id, 
	(
		SELECT term_taxonomy_id
		FROM wp_term_taxonomy tax
		INNER JOIN wp_terms term ON tax.term_id = term.term_id
		WHERE term.slug = 'galleries' AND tax.taxonomy = 'category'
	) as term_taxonomy_id
	FROM `minnpost.drupal`.node n
	INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
	WHERE n.type = 'slideshow'
;


# Update category counts.
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;



# Section 6 - Comments

# Comments
# Keeps unapproved comments hidden.
# Incorporates change noted here: http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-32169
# mp change: uses the pid field from Drupal for the comment_parent field
# mp change: keep the value 200 characters or less
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_comments
	(comment_ID, comment_post_ID, comment_date, comment_content, comment_parent, comment_author,
	comment_author_email, comment_author_url, comment_approved, user_id)
	SELECT DISTINCT
		cid, nid, FROM_UNIXTIME(timestamp), comment, pid, name,
		mail, SUBSTRING(homepage, 1, 200), status, uid
		FROM `minnpost.drupal`.comments
;


# Update comments count on wp_posts table.
UPDATE `minnpost.wordpress`.wp_posts
	SET `comment_count` = (
		SELECT COUNT(`comment_post_id`)
		FROM `minnpost.wordpress`.wp_comments
		WHERE `minnpost.wordpress`.wp_posts.`id` = `minnpost.wordpress`.wp_comments.`comment_post_id`
	)
;





# OPTIONAL ADDITIONS -- REMOVE ALL BELOW IF NOT APPLICABLE TO YOUR CONFIGURATION




# stuff for users:
# If we change the inner join to left join on the insert into wp_users, we can get all users inserted
# however, this will break the roles. we need to have the roles at least created in WordPress before doing this
# and then we will need some joins to do the inserting


# example:
#SELECT DISTINCT u.uid, 'wp_capabilities', 'a:1:{s:6:"author";s:1:"1";}', re.name
#FROM `minnpost.drupal`.users u
#INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
#INNER JOIN `minnpost.drupal`.role re USING (rid)
#WHERE (1
	# Uncomment and enter any email addresses you want to exclude below.
	# AND u.mail NOT IN ('test@example.com')
#)

# SELECT DISTINCT
# 	u.uid, u.mail, NULL, u.name, u.mail,
# 	FROM_UNIXTIME(created), '', 0, u.name
# FROM `minnpost.drupal`.users u
# INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
# INNER JOIN `minnpost.drupal`.role role USING (rid)
# WHERE (1
# 	AND role.name IN ('administrator', 'author', 'author two', 'editor', 'super admin')
	# Uncomment and enter any email addresses you want to exclude below.
	# AND u.mail NOT IN ('test@example.com')
# )


# INSERT ALL USERS
# we should put in a spam flag into the Drupal table so we don't have to import all those users
INSERT IGNORE INTO `minnpost.wordpress`.wp_users
	(ID, user_login, user_pass, user_nicename, user_email,
	user_registered, user_activation_key, user_status, display_name)
	SELECT DISTINCT
		u.uid as ID, u.mail as user_login, NULL as user_pass, u.name as user_nicename, u.mail as user_email,
		FROM_UNIXTIME(created) as user_registered, '' as user_activation_key, 0 as user_status, u.name as display_name
	FROM `minnpost.drupal`.users u
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND u.uid != 0
	)
;


# when we add multiple permissions per user, it is fixed by the Merge Serialized Fields plugin.

# Sets bronze member level capabilities for members
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"member_bronze";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - bronze')
	)
;
# custom member level field
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'member_level' as meta_key, 'MinnPost Bronze' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - bronze')
	)
;

# Sets silver member level capabilities for members
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"member_silver";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - silver')
	)
;
# custom member level field
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'member_level' as meta_key, 'MinnPost Silver' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - silver')
	)
;

# Sets gold member level capabilities for members
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"member_gold";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - gold')
	)
;
# custom member level field
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'member_level' as meta_key, 'MinnPost Gold' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - gold')
	)
;

# Sets platinum member level capabilities for members
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"member_platinum";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - platinum')
	)
;
# custom member level field
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'member_level' as meta_key, 'MinnPost Platinum' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('member - platinum')
	)
;


# Assign author permissions.
# Sets all authors to "author" by default; next section can selectively promote individual authors
# parameter: line 1088 contains the Drupal permission roles that we want to migrate
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"author";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('author', 'author two', 'editor', 'user admin', 'administrator')
	)
;


# Assign administrator permissions
# Set all Drupal super admins to "administrator"
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:13:"administrator";s:1:"1";}' as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
	INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name = 'super admin'
	)
;



# save user first and last name, if we have them as users in Drupal
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT u.uid as user_id, 'first_name' as meta_key, pv.`value` as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.profile_values pv ON u.uid = pv.uid 
	INNER JOIN `minnpost.drupal`.profile_fields pf ON pv.fid = pf.fid
	INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
	INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
	WHERE pf.fid = 4
;
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT u.uid as user_id, 'last_name' as meta_key, pv2.`value` as meta_value
	FROM `minnpost.drupal`.users u
	INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
	INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
	WHERE pf2.fid = 5
;


# Drupal authors who may or may not be users
# these get inserted as posts with a type of guest-author, for the plugin
# this one does take the vid into account (we do track revisions)
INSERT INTO `minnpost.wordpress`.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_modified, post_type, `post_status`)
	SELECT DISTINCT
		n.nid `id`,
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		n.title `post_title`,
		'' `post_excerpt`,
		CONCAT('cap-', substring_index(a.dst, '/', -1)) `post_name`,
		FROM_UNIXTIME(n.changed) `post_modified`,
		'guest-author' `post_type`,
		'publish' `post_status`
	FROM `minnpost.drupal`.node n
	INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
	INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
	LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
;


# add the user_node_id_old field for tracking Drupal node IDs for authors
ALTER TABLE wp_terms ADD user_node_id_old BIGINT(20);


# Temporary table for user terms
CREATE TABLE `wp_terms_users` (
	`term_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	`name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`slug` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`term_group` bigint(10) NOT NULL DEFAULT '0',
	PRIMARY KEY (`term_id`),
	KEY `slug` (`slug`(191)),
	KEY `name` (`name`(191))
);


# put the user terms in the temp table
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_users (term_id, name, slug)
	SELECT DISTINCT
	nid `term_id`,
	n.title `name`,
	substring_index(a.dst, '/', -1) `slug`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
		WHERE n.type = 'author'
		ORDER BY n.nid
;


# Put all Drupal authors into terms; store old node ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, user_node_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_users u
	ORDER BY term_id
;


# get rid of that temporary author table
DROP TABLE wp_terms_users;


# Create taxonomy for each author
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
	SELECT term_id, 'author', CONCAT(p.post_title, ' ', t.name, ' ', p.ID) as description
	FROM wp_terms t
	INNER JOIN wp_posts p ON t.`user_node_id_old` = p.ID
;


# Create relationships for each story to the author it had in Drupal
# Track this relationship by the user_node_id_old field
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT author.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
		FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_op_author author ON term.user_node_id_old = author.field_op_author_nid
			INNER JOIN `minnpost.drupal`.node n ON author.nid = n.nid AND author.vid = n.vid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			WHERE tax.taxonomy = 'author'
;


# use the title as the user's display name
# this might be all the info we have about the user
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-display_name' `meta_key`,
		n.title `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
;


# make a slug for user's login
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_login' `meta_key`,
		substring_index(a.dst, '/', -1) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
;


# update count for authors
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# add a temporary constraint for email addresses so we don't add duplicates
ALTER TABLE `minnpost.wordpress`.wp_postmeta ADD CONSTRAINT temp_email UNIQUE (post_id, meta_key, meta_value(64));


# add the email address for the author if we have one
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_email' `meta_key`,
		REPLACE(link.field_link_multiple_url, 'mailto:', '') `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_link_multiple link USING (nid, vid)
		WHERE field_link_multiple_title = 'Email the author'
;


# add the author's twitter account if we have it
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-twitter' `meta_key`,
		CONCAT('https://twitter.com/', REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(link.field_link_multiple_url, 'http://www.twitter.com/', ''), 'http://twitter.com/', ''), '@', ''), 'https://twitter.com/', ''), '#%21', ''), '/', '')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_link_multiple link USING (nid, vid)
		WHERE field_link_multiple_title LIKE '%witter%'
;


# add the author's job title if we have it
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-job-title' `meta_key`,
		author.field_op_author_jobtitle_value `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		INNER JOIN `minnpost.drupal`.users user ON author.field_author_user_uid = user.uid
		WHERE author.field_op_author_jobtitle_value IS NOT NULL
;


# if the author is linked to a user account, link them
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-linked_account' `meta_key`,
		user.mail `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		INNER JOIN `minnpost.drupal`.users user ON author.field_author_user_uid = user.uid
;


# if the linked user has an email address, add it
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_email' `meta_key`,
		user.mail `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
		INNER JOIN `minnpost.drupal`.users user ON author.field_author_user_uid = user.uid
;

# drop that temporary constraint
ALTER TABLE `minnpost.wordpress`.wp_postmeta DROP INDEX temp_email;


# Change permissions for admins.
# Add any specific user IDs to IN list to make them administrators.
# User ID values are carried over from `minnpost.drupal`.
# we shouldn't ever need to use this
#UPDATE `minnpost.wordpress`.wp_usermeta
#	SET meta_value = 'a:1:{s:13:"administrator";s:1:"1";}'
#	WHERE user_id IN (1) AND meta_key = 'wp_capabilities'
#;


# Reassign post authorship.
# we probably don't need this i think
#UPDATE `minnpost.wordpress`.wp_posts
#	SET post_author = NULL
#	WHERE post_author NOT IN (SELECT DISTINCT ID FROM `minnpost.wordpress`.wp_users)
#;


# update count for authors again
# we probably don't need this anymore since we commented out the one above
#UPDATE wp_term_taxonomy tt
#	SET `count` = (
#		SELECT COUNT(tr.object_id)
#		FROM wp_term_relationships tr
#		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
#	)
#;


# assign authors from author nodes to stories where applicable
# not sure this query is useful at all
# UPDATE `minnpost.wordpress`.wp_posts AS posts INNER JOIN `minnpost.drupal`.content_field_op_author AS authors ON posts.ID = authors.nid SET posts.post_author = authors.field_op_author_nid;

# get rid of that user_node_id_old field if we are done migrating into wp_term_relationships
ALTER TABLE wp_terms DROP COLUMN user_node_id_old;


# main images as featured images for posts
# this will be the default if another version is not present
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', f.filepath) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
;

# for audio posts, there is no main image field in Drupal
# for video posts, there is no main image field in Drupal
# for slideshow posts, there is no main image field in Drupal


# use the detail suffix for the single page image url field
# this loads the detail image from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_mp_image_settings_main_image' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/articles', '/imagecache/article_detail/images/articles')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
		WHERE i.field_main_image_fid IS NOT NULL
;


# for audio posts, there is no single page image field in Drupal
# for video posts, there is no single page image field in Drupal
# for slideshow posts, there is no single page image field in Drupal


# thumbnail version
# this is the small thumbnail from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/thumbnail/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
;


# insert thumbnails as posts
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/thumbnail/images/thumbnails/articles')) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
;

# this _wp_imported_metadata field is fixed by the Deserialize Metadata plugin: https://wordpress.org/extend/plugins/deserialize-metadata/


# insert metadata for thumbnails - this relates to the image post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
	ID `post_id`,
	'_wp_imported_metadata' `meta_key`,
	i.field_thumbnail_image_data `meta_value`
	FROM `minnpost.wordpress`.wp_posts p
	LEFT OUTER JOIN `minnpost.drupal`.content_field_thumbnail_image i ON p.post_parent = i.nid
	WHERE post_type = 'attachment' AND i.field_thumbnail_image_data IS NOT NULL
	GROUP BY post_id
;


# thumbnail version for audio posts
# this is the small thumbnail from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
;


# insert audio thumbnails as posts
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
;


# insert metadata for audio thumbnails - this relates to the image post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
	ID `post_id`,
	'_wp_imported_metadata' `meta_key`,
	a.field_op_audio_thumbnail_data `meta_value`
	FROM `minnpost.wordpress`.wp_posts p
	LEFT OUTER JOIN `minnpost.drupal`.content_type_audio a ON p.post_parent = a.nid
	WHERE post_type = 'attachment' AND a.field_op_audio_thumbnail_data IS NOT NULL
	GROUP BY post_id
;


# thumbnail version for video posts
# this is the small thumbnail from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
;


# insert video thumbnails as posts
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
;


# insert metadata for video thumbnails - this relates to the image post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
	ID `post_id`,
	'_wp_imported_metadata' `meta_key`,
	v.field_op_video_thumbnail_data `meta_value`
	FROM `minnpost.wordpress`.wp_posts p
	LEFT OUTER JOIN `minnpost.drupal`.content_type_video v ON p.post_parent = v.nid
	WHERE post_type = 'attachment' AND v.field_op_video_thumbnail_data IS NOT NULL
	GROUP BY post_id
;


# thumbnail version for gallery posts
# this is the small thumbnail from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/slideshow', '/imagecache/thumbnail/images/thumbnails/slideshow')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_slideshow s USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON s.field_op_slideshow_thumb_fid = f.fid
;


# insert gallery thumbnails as posts
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/slideshow', '/imagecache/thumbnail/images/thumbnails/slideshow')) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_slideshow s USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON s.field_op_slideshow_thumb_fid = f.fid
;


# insert metadata for gallery thumbnails - this relates to the image post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
	ID `post_id`,
	'_wp_imported_metadata' `meta_key`,
	s.field_op_slideshow_thumb_data `meta_value`
	FROM `minnpost.wordpress`.wp_posts p
	LEFT OUTER JOIN `minnpost.drupal`.content_type_slideshow s ON p.post_parent = s.nid
	WHERE post_type = 'attachment' AND s.field_op_slideshow_thumb_fid IS NOT NULL
	GROUP BY post_id
;


# insert metadata for thumbnails - this relates to the content post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
		post_parent `post_id`,
		'_thumbnail_id' `meta_key`,
		ID `meta_value`
		FROM wp_posts
		WHERE post_type = 'attachment'
;


# insert main images as posts
# we put this after the other image stuff because the above query treats all attachment posts as if they are thumbnails
# and these are not thumbnails
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/articles', '/imagecache/article_detail/images/articles')) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
;


# insert main image id as cmb2 field value
# this now takes vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
		post_parent `post_id`,
		'_mp_image_settings_main_image_id' `meta_key`,
		ID `meta_value`
		FROM wp_posts p
		LEFT OUTER JOIN `minnpost.drupal`.node n ON p.post_parent = n.nid
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_main_image i USING (nid, vid)
		WHERE post_type = 'attachment' AND guid LIKE '%/imagecache/article_detail/images/articles%'
;


# insert metadata for main images - this relates to the image post ID
# this now takes vid into account
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
		ID `post_id`,
		'_wp_imported_metadata' `meta_key`,
		i.field_main_image_data `meta_value`
		FROM `minnpost.wordpress`.wp_posts p
			LEFT OUTER JOIN `minnpost.drupal`.node n ON p.post_parent = n.nid
			LEFT OUTER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			LEFT OUTER JOIN `minnpost.drupal`.content_field_main_image i USING (nid, vid)
			WHERE post_type = 'attachment' AND i.field_main_image_data IS NOT NULL
			GROUP BY post_id
;


# insert credit field for main images
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
		ID `post_id`,
		'_media_credit' `meta_key`,
		c.field_main_image_credit_value `meta_value`
		FROM `minnpost.wordpress`.wp_posts p
		LEFT OUTER JOIN `minnpost.drupal`.content_field_main_image_credit c ON p.post_parent = c.nid
		WHERE post_type = 'attachment' AND c.field_main_image_credit_value IS NOT NULL
		GROUP BY post_id
;


# might as well use the standard thumbnail meta key with the same value for audio
# wordpress will read this part for us in the admin
# do we need both?
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
;


# insert local audio files as posts so they show in media library
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', f.filepath) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_audio_file_fid = f.fid
;

# there is no alt or caption info for audio files stored in drupal


# might as well use the standard thumbnail meta key with the same value for video
# wordpress will read this part for us in the admin
# do we need both?
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
;


# insert local video files as posts so they show in media library
# this one does take the vid into account
INSERT INTO `minnpost.wordpress`.wp_posts
	(post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		REPLACE(CONCAT('https://www.minnpost.com/', f.filepath), '.flv', '.mp4') `guid`,
		'attachment' `post_type`,
		'video/mp4' `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_flash_file_fid = f.fid
;

# there is no alt or caption info for video files stored in drupal


# might as well use the standard thumbnail meta key with the same value for slideshow
# wordpress will read this part for us in the admin
# do we need both?
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/slideshow', '/imagecache/thumbnail/images/thumbnails/slideshow')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_slideshow s USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON s.field_op_slideshow_thumb_fid = f.fid
;


# insert local gallery files as posts so they show in media library
# need to watch carefully to see that the id field doesn't have to be removed due to any that wp has already created
# if it does, we need to create a temporary table to store the drupal node id, because that is how the gallery shortcode works
# 3/23/17: right now this fails because most of the titles are null. need to see if we can just get the ones that aren't null?
# 4/12/17: i don't know when this was fixed but it seems to be fine
# 5/15/17: started using the vid to track revisions. need to see if it changes anything.
INSERT INTO `minnpost.wordpress`.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_status, post_parent, guid, post_type, post_mime_type)
	SELECT DISTINCT
		n2.nid `id`,
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		f.filename `post_title`,
		'' `post_excerpt`,
		f.filename `post_name`,
		'inherit' `post_status`,
		n.nid `post_parent`,
		CONCAT('https://www.minnpost.com/', f.filepath) `guid`,
		'attachment' `post_type`,
		f.filemime `post_mime_type`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_op_slideshow_images s USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.node n2 ON s.field_op_slideshow_images_nid = n2.nid
		LEFT OUTER JOIN `minnpost.drupal`.content_field_main_image i ON n2.nid = i.nid
		LEFT OUTER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
		WHERE n.type = 'slideshow' AND f.filename IS NOT NULL
;

# there is alt / caption info

# see if this works
# insert metadata for gallery images - this relates to the image post ID
# this doesn't really seem to need any vid stuff
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT
	ID `post_id`,
	'_wp_imported_metadata' `meta_key`,
	i.field_main_image_data `meta_value`
	FROM `minnpost.wordpress`.wp_posts p
	INNER JOIN `minnpost.drupal`.content_field_op_slideshow_images s ON p.post_parent = s.nid
	INNER JOIN `minnpost.drupal`.node n2 ON s.field_op_slideshow_images_nid = n2.nid
	INNER JOIN `minnpost.drupal`.content_field_main_image i ON n2.nid = i.nid
	# GROUP BY post_id - I think this grouping is problematic for the slideshow images. maybe it only does one image per story?
;


# feature thumbnail
# this is the larger thumbnail image that shows on section pages from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/feature/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/articles%'
;


# feature large thumbnail
# this is the larger thumbnail image that shows on the top of the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_large' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/feature_large/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/articles%'
;


# feature middle thumbnail
# this is the middle thumbnail image that shows on the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_middle' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/feature_middle/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/articles%'
;


# feature thumbnail for audio posts
# this is the larger thumbnail image that shows on section pages from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/feature/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/audio%'
;


# feature large thumbnail for audio posts
# this is the larger thumbnail image that shows on the top of the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_large' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/feature_large/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/audio%'
;


# feature middle thumbnail for audio posts
# this is the middle thumbnail image that shows on the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_middle' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/feature_middle/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/audio%'
;


# feature thumbnail for video posts
# this is the larger thumbnail image that shows on section pages from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/feature/images/thumbnails/video')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/video%'
;


# feature large thumbnail for video posts
# this is the larger thumbnail image that shows on the top of the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_large' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/feature_large/images/thumbnails/video')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/video%'
;


# feature middle thumbnail for video posts
# this is the middle thumbnail image that shows on the homepage from cache folder
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature_middle' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/feature_middle/images/thumbnails/video')) `meta_value`
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
		INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/video%'
;


# more metadata for images; this is caption only if it is stored elsewhere
# the deserialize metadata plugin does not overwrite these values
# this one does take the vid into account
UPDATE `minnpost.wordpress`.wp_posts
	JOIN `minnpost.drupal`.node ON wp_posts.ID = node.nid
	LEFT OUTER JOIN `minnpost.drupal`.node_revisions r ON node.vid = r.vid
	SET wp_posts.post_excerpt = r.body
	WHERE wp_posts.post_type = 'attachment' AND r.body != ''
;


# this is homepage size metadata, field homepage_image_size, for posts
# this one does take the vid into account
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		nid as post_id, '_mp_image_settings_homepage_image_size' as meta_key, field_hp_image_size_value as meta_value
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_hp_image_size s USING(nid, vid)
		WHERE s.field_hp_image_size_value IS NOT NULL
;


# fix homepage size vars to match wordpress better
# these don't really seem to need any vid stuff

# medium
UPDATE `minnpost.wordpress`.wp_postmeta
	SET meta_value = 'feature_middle'
	WHERE meta_value = 'medium' AND meta_key = '_mp_image_settings_homepage_image_size'
;


# large
UPDATE `minnpost.wordpress`.wp_postmeta
	SET meta_value = 'feature_large'
	WHERE meta_value = 'large' AND meta_key = '_mp_image_settings_homepage_image_size'
;





# WordPress Settings
# if there are settings we can set all the time and make life easier, do that here
UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 130
	WHERE option_name = 'thumbnail_size_w'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 85
	WHERE option_name = 'thumbnail_size_h'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 1
	WHERE option_name = 'thumbnail_crop'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 190
	WHERE option_name = 'medium_size_w'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 9999
	WHERE option_name = 'medium_size_h'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 640
	WHERE option_name = 'large_size_w'
;

UPDATE `minnpost.wordpress`.wp_options
	SET option_value = 500
	WHERE option_name = 'large_size_h'
;


# Redirects for the Redirection plugin - https://wordpress.org/plugins/redirection/
INSERT INTO `minnpost.wordpress`.wp_redirection_items
	(`id`, `url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
	SELECT DISTINCT
		p.rid `id`,
		CONCAT('/', p.source) `url`,
		0 `regex`,
		0 `position`,
		1 `last_count`,
		FROM_UNIXTIME(p.last_used) `last_access`,
		1 `group_id`,
		'enabled' `status`,
		'url' `action_type`,
		301 `action_code`,
		CONCAT(
			(
			SELECT option_value
			FROM `minnpost.wordpress`.wp_options
			WHERE option_name = 'siteurl'
			),
			'/',
			IFNULL(a.dst, p.redirect)) `action_data`,
		'url' `match_type`,
		'' `title`
		FROM `minnpost.drupal`.path_redirect p
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON p.redirect = a.src
;


# create redirects for the gallery stories
INSERT INTO `minnpost.wordpress`.wp_redirection_items
	(`url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
	SELECT DISTINCT
		CONCAT('/galleries/', p.post_name) `url`,
		0 `regex`,
		0 `position`,
		1 `last_count`,
		p.post_modified `last_access`,
		1 `group_id`,
		'enabled' `status`,
		'url' `action_type`,
		301 `action_code`,
		CONCAT(
			(
			SELECT option_value
			FROM `minnpost.wordpress`.wp_options
			WHERE option_name = 'siteurl'
			),
			'/',
			CONCAT('?p=', p.ID)) `action_data`,
		'url' `match_type`,
		'' `title`
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN `minnpost.drupal`.node n ON p.ID = n.nid
		WHERE n.type = 'slideshow'
;


# zoninator zones (like nodequeues)

# add zoninator terms
INSERT INTO `minnpost.wordpress`.wp_terms
	(name, slug, term_group)
	SELECT DISTINCT
		q.title `name`,
		replace(trim(lower(q.title)), ' ', '-') `slug`,
		0 `term_group`
	FROM `minnpost.drupal`.nodequeue_queue q
	WHERE q.title != 'Homepage Columns' # we can't use a zone for this because the categories aren't posts in wp
;


# add zoninator taxonomies
INSERT IGNORE INTO `minnpost.wordpress`.wp_term_taxonomy
	(term_id, taxonomy, description, parent, count)
	SELECT DISTINCT
		term_id `term_id`,
		'zoninator_zones' `taxonomy`,
		CONCAT('a:1:{s:11:"description";s:15:"', t.name, '";}') `description`,
		0 `parent`,
		0 `count`
		FROM `minnpost.drupal`.nodequeue_queue q
		INNER JOIN `minnpost.wordpress`.wp_terms t ON q.title = t.name
;


# add posts to the zones
# this does not have a vid to use
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			CONCAT('_zoninator_order_', t.term_id) `meta_key`,
			ABS(
				CAST(
					n.position as SIGNED
				)
				- 
				CAST(
					(
						SELECT MAX(position)
						FROM `minnpost.drupal`.nodequeue_nodes nq
						WHERE nq.qid = q.qid
					) as SIGNED
				)
			) + 1 as `meta_value`
			FROM `minnpost.drupal`.nodequeue_nodes n
			INNER JOIN `minnpost.drupal`.nodequeue_queue q ON n.qid = q.qid
			INNER JOIN `minnpost.wordpress`.wp_terms t ON q.title = t.name
;


# Temporary table for menus
CREATE TABLE `wp_menu` (
	`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	`name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`title` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`placement` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	PRIMARY KEY (`id`)
);


# Temporary table for menu items
CREATE TABLE `wp_menu_items` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `menu-name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `menu-item-title` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `menu-item-url` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `menu-item-parent` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT '',
  `menu-item-parent-id` bigint(20) unsigned DEFAULT NULL,
  `menu-item-status` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'publish',
  PRIMARY KEY (`id`)
)


# add menus
# parameter: line 2387 contains the menu types in drupal that we don't want to migrate
# todo: we need to figure out what to do with the user menu (login, logout, etc.) in wordpress
INSERT INTO `minnpost.wordpress`.wp_menu
	(name, title, placement)
	SELECT DISTINCT
		m.menu_name `name`,
		m.title `title`,
		REPLACE(TRIM(LOWER(m.title)), ' ', '_') `placement`
		FROM `minnpost.drupal`.menu_custom m
		WHERE m.menu_name NOT IN ('admin', 'devel', 'navigation', 'features', 'menu-top-menu')
;


# add menu items
# parameter: line 2422 important parameter to keep out/force some urls because of how they're stored in drupal
INSERT INTO `minnpost.wordpress`.wp_menu_items
	(`menu-name`, `menu-item-title`, `menu-item-url`, `menu-item-parent`)
	SELECT DISTINCT
		m.menu_name `menu-name`,
		l.link_title `menu-item-title`,
		REPLACE(IFNULL(a.dst, l.link_path), '<front>', '/') `menu-item-url`,
		(
			SELECT link_title
			FROM `minnpost.drupal`.menu_links
			WHERE mlid = l.plid
		) as `menu-item-parent`
		FROM `minnpost.drupal`.menu_links l
		INNER JOIN `minnpost.wordpress`.wp_menu wm ON wm.name = menu_name
		INNER JOIN `minnpost.drupal`.menu_custom m USING(menu_name)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON l.link_path = a.src
		LEFT OUTER JOIN `minnpost.drupal`.node n ON a.src = CONCAT('node/', n.nid)
		LEFT OUTER JOIN `minnpost.drupal`.term_data t ON l.link_path = CONCAT('taxonomy/term/', t.tid)
		WHERE l.hidden != 1 AND l.module = 'menu' AND (
			(
				n.status = 1 OR l.external = 1 OR n.nid IS NULL AND n.status != 0
			)
			OR
			(
				n.status = 1 AND a.dst IS NOT NULL AND n.status != 0
			)
			OR
			(
				l.router_path = 'taxonomy/term/%' AND t.tid IS NOT NULL
			)
		) OR l.link_path IN ('events', 'support')
		ORDER BY menu_name, plid, l.weight
;


# get rid of those temporary menu tables
# can't run this until after the migrate-random-things.php task runs twice. once to add parent items, once to add their children if applicable
DROP TABLE wp_menu;
DROP TABLE wp_menu_items;


# replace content when necessary

# use widgets for news by region
# these numbers change if we have to recreate the widgets. ugh.
UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = '<!--break-->
[widget_instance id="minnpostspills_widget-50" format="0"]

[widget_instance id="minnpostspills_widget-46" format="0"]

[widget_instance id="minnpostspills_widget-18" format="0"]

[widget_instance id="minnpostspills_widget-45" format="0"]'
	WHERE ID = 30750;
;

# note about widgets: the imported json does not set the target by url field
# also, resetting the database with all these queries does not break the widgets, so setting them up really only has to be done once


# create ad table for migrating
CREATE TABLE `ads` (
	`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
	`tag` varchar(255) NOT NULL DEFAULT '',
	`tag_id` varchar(255) NOT NULL DEFAULT '',
	`tag_name` varchar(255) NOT NULL DEFAULT '',
	`priority` int(11) NOT NULL,
	`conditions` text NOT NULL,
	`result` text NOT NULL,
	`stage` tinyint(1) NOT NULL DEFAULT '0',
	PRIMARY KEY (`id`)
);


# ads
# this allows us to get the ad data into a wordpress table so we can manipulate it into ads with a plugin
# currently using the migrate random things plugin to work on this
INSERT IGNORE INTO `minnpost.wordpress`.ads
	(tag, tag_id, tag_name, priority, conditions, result)
	SELECT DISTINCT delta as tag, name as tag_id, tag as tag_name, weight as priority, conditions as conditions, reactions as result
	FROM `minnpost.drupal`.context c
		INNER JOIN `minnpost.drupal`.blocks b ON c.reactions LIKE CONCAT('%', b.delta, '%')
		WHERE module = 'minnpost_ads' AND theme = 'siteskin'
		ORDER BY weight DESC, delta
;


# get rid of the temporary ad table
DROP TABLE ads;