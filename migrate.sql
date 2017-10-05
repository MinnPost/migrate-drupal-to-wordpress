# DRUPAL-TO-WORDPRESS CONVERSION SCRIPT


# Changelog

	# 04.11.2016 - Forked for MinnPost by Jonathan Stegall; gradually expanded over approximately forever
	# 07.29.2010 - Updated by Scott Anderson / Room 34 Creative Services http://blog.room34.com/archives/4530
	# 02.06.2009 - Updated by Mike Smullin http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/
	# 05.15.2007 - Updated by D’Arcy Norman http://www.darcynorman.net/2007/05/15/how-to-migrate-from-drupal-5-to-wordpress-2/
	# 05.19.2006 - Created by Dave Dash http://spindrop.us/2006/05/19/migrating-from-drupal-47-to-wordpress/

	# This assumes that WordPress and Drupal are in separate databases, named 'wordpress' and 'drupal'.
	# If your database names differ, adjust these accordingly.


# Section 1 - Reset. The order is important here.

	# Empty previous content from WordPress database.
	TRUNCATE TABLE `minnpost.wordpress`.wp_comments;
	TRUNCATE TABLE `minnpost.wordpress`.wp_links;
	TRUNCATE TABLE `minnpost.wordpress`.wp_postmeta;
	TRUNCATE TABLE `minnpost.wordpress`.wp_posts;
	TRUNCATE TABLE `minnpost.wordpress`.wp_term_relationships;
	DELETE FROM `minnpost.wordpress`.wp_term_taxonomy WHERE term_taxonomy_id > 1;
	DELETE FROM `minnpost.wordpress`.wp_terms WHERE term_id > 1;
	TRUNCATE TABLE `minnpost.wordpress`.wp_termmeta;
	TRUNCATE TABLE `minnpost.wordpress`.wp_redirection_items;

	# If you're not bringing over multiple Drupal authors, comment out these lines and the other
	# author-related queries near the bottom of the script.
	# This assumes you're keeping the default admin user (user_id = 1) created during installation.
	DELETE FROM `minnpost.wordpress`.wp_users WHERE ID > 1;
	DELETE FROM `minnpost.wordpress`.wp_usermeta WHERE user_id > 1;

	# it is worth clearing out the individual object maps from the salesforce plugin because ids for things change, and this could break mappings anyway
	TRUNCATE TABLE `minnpost.wordpress`.wp_object_sync_sf_object_map;

	# reset the deserialize value so it can start over with deserializing
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 1
		WHERE option_name = 'deserialize_metadata_last_post_checked'
	;

	# this is where we stop deleting data to start over



# Section 2 - Core Posts. The order is important here (we use the post ID from Drupal).

	# Posts from Drupal stories
	# Keeps private posts hidden.
	# parameter: line 75 contains the Drupal content types that we want to migrate
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
	# parameter: line 85 must contain the content types from parameter in line 75 that should be imported as 'posts'
	# newsletter and page should stay as they are
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


	# Fix image urls in post content
	# in our case, we use this to make the urls absolute, at least for now
	# no need for vid stuff
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
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



# Section 3 - Tags, Post Formats, and their taxonomies and relationships to posts. The order is important here because we use the nid field as the term_id value from Drupal.

	# Tags from Drupal vocabularies
	# Using REPLACE prevents script from breaking if Drupal contains duplicate terms.
	# permalinks are going to break for tags whatever we do, because drupal puts them all into folders (ie https://www.minnpost.com/category/social-tags/architect)
	# we have created redirects that point to the correct urls for tags - /tag/slug; this is different than /slug for categories
	# this should prevent issues because of slugs that represent tags and categories
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
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id `term_id`, 'post_format' `taxonomy`, '' `description`
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
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id `term_id`, 'post_format' `taxonomy`, '' `description`
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
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id `term_id`, 'post_format' `taxonomy`, '' `description`
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



# Section 4 - Users and Authors, and their terms and taxonomies and relationships to posts. Order is important here because we use the post ID for authors.

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


	# Drupal authors who may or may not be users
	# these get inserted as posts with a type of guest-author, for the plugin
	# this one does take the vid into account (we do track revisions)
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			'' `post_content`,
			n.title `post_title`,
			'' `post_excerpt`,
			CONCAT('cap-', substring_index(a.dst, '/', -1)) `post_name`,
			'' `to_ping`,
			'' `pinged`,
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


	# Create relationships for each story to the authors it had in Drupal
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


	# get rid of that user_node_id_old field if we are done migrating into wp_term_relationships
	ALTER TABLE wp_terms DROP COLUMN user_node_id_old;



# Section 5 - Post Images (including authors) and other local file attachments, and attach them to posts. Order has to be after users because we use the post id for users above but we don't have one to use here for files, so it autoincrements. But we can skip this section if we're testing other stuff.
	
	# WordPress Settings for image uploads


	# wordpress generates these size files when a new image gets uploaded into the library
	# however we need the remote urls to exist in the database for all the existing posts
	# every method that displays images should work like this:
	#	1. is there a wordpress image for this post, and the size, that belongs here? if so, display it
	#	2. if not, is there a field in the database for this image size and this post? if so, display it


	# thumbnail size
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


	# medium size
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 190
		WHERE option_name = 'medium_size_w'
	;

	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 9999
		WHERE option_name = 'medium_size_h'
	;


	# large size (article_detail from drupal)
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 640
		WHERE option_name = 'large_size_w'
	;

	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 500
		WHERE option_name = 'large_size_h'
	;


	# we can add additional sizes that get generated in the theme itself
	# article inset is used only for partner offer stuff


	# notes:
	# 	for audio posts, there is no main image field in Drupal but there is a thumbnail
	# 	for video posts, there is no main image field in Drupal but there is a thumbnail
	# 	for slideshow posts, there is no main image field in Drupal but there is a thumbnail
	#	for authors, there is a main image and a thumbnail


	# gallery images for gallery posts

	# insert local gallery files as posts so they show in media library
	# need to watch carefully to see that the id field doesn't have to be removed due to any that wp has already created
	# if it does, we need to create a temporary table to store the drupal node id, because that is how the gallery shortcode works
	# 3/23/17: right now this fails because most of the titles are null. need to see if we can just get the ones that aren't null?
	# 4/12/17: i don't know when this was fixed but it seems to be fine
	# 5/15/17: started using the vid to track revisions. need to see if it changes anything.
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
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


	# insert gallery thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
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


	# audio/video files for audio and video posts


	# insert local audio files as posts so they show in media library
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
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


	# insert local video files as posts so they show in media library
	# this one does take the vid into account
	# 8/3/17: this is currently empty; we don't seem to need it anymore
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
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


	# post main images

	# we store the drupal_file_id as a temp field and use it for the meta insert

	# add the image_post_file_id_old field for tracking Drupal node IDs for posts
	ALTER TABLE wp_posts ADD image_post_file_id_old BIGINT(20);


	# insert main images as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/articles', '/imagecache/article_detail/images/articles')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
	;


	# insert the id and url as meta fields for the main image for each post
	# each needs the post id for the story
	# _mp_post_main_image_id (the image post id)
	# _mp_post_main_image (full url, at least during the migration phase; it might change when we're uploading natively but who knows)

	# post id for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_post_main_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment'
	;


	# url for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_post_main_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment'
	;


	# insert author photos as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/author', '/imagecache/author_photo/images/author')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_author_photo_fid = f.fid
	;


	# post id for author image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_author_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			INNER JOIN `minnpost.wordpress`.wp_posts parent ON p.post_parent = parent.ID
			WHERE p.post_type = 'attachment' and parent.post_type = 'guest-author'
	;


	# url for author image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_author_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			INNER JOIN `minnpost.wordpress`.wp_posts parent ON p.post_parent = parent.ID
			WHERE p.post_type = 'attachment' and parent.post_type = 'guest-author'
	;


	# we shouldn't need to null the temp value because it all comes from drupal's files table


	# insert post thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/thumbnail/images/thumbnails/articles')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE n.type IN ('article')
	;


	# insert full page article thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/thumbnail/images/thumbnails/fullpagearticles')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE n.type = 'article_full'
	;


	# insert audio thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
	;


	# insert video thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
	;


	# insert slideshow thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/slideshow', '/imagecache/thumbnail/images/thumbnails/slideshow')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
	;


	# we need to check this again and make sure there are no duplicate image urls bc they will break


	# insert the id and url as meta fields for the thumbnail image for each post/post type
	# each needs the post id for the item
	# _mp_post_thumbnail_image_id (the image post id)
	# _mp_post_thumbnail_image (full url, at least during the migration phase; it might change when we're uploading natively but who knows)

	# post id for thumbnail image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_post_thumbnail_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND p.ID NOT LIKE '%imagecache/article_detail%'
	;


	# url for thumbnail image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_post_thumbnail_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND p.guid NOT LIKE '%imagecache/article_detail%'
	;


	# i am not totally sure we will have to do this after the meta_value NOT LIKE, but in case we need it here it is
	DELETE FROM `minnpost.wordpress`.wp_postmeta
	WHERE meta_key = '_mp_post_thumbnail_image_id' AND meta_value LIKE '%imagecache/article_detail%'
	;


	# author thumbnail does not go into the interface so we can just store it as a meta field instead of a post


	# then we can get rid of that temp file id field
	ALTER TABLE wp_posts DROP COLUMN image_post_file_id_old;


	# sizes that are not in the ui because they get autogenerated


	# for posts

	# feature thumbnail
	# this is the larger thumbnail image that shows on section pages from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_middle' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/feature_middle/images/thumbnails/articles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/articles%'
	;


	# newsletter thumbnail
	# this is the thumbnail image that shows on newsletters
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_newsletter' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/newsletter_thumb/images/thumbnails/articles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/articles%'
	;


	# author teaser thumbnail for stories
	# this gets used on that recent stories widget, at least
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_author_teaser' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/author_teaser/images/thumbnails/articles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/articles%'
	;


	# for full page article

	# feature thumbnail
	# this is the larger thumbnail image that shows on section pages from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/feature/images/thumbnails/fullpagearticles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/fullpagearticles%'
	;


	# feature large thumbnail
	# this is the larger thumbnail image that shows on the top of the homepage from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature_large' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/feature_large/images/thumbnails/fullpagearticles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/fullpagearticles%'
	;


	# feature middle thumbnail
	# this is the middle thumbnail image that shows on the homepage from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature_middle' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/feature_middle/images/thumbnails/fullpagearticles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/fullpagearticles%'
	;


	# newsletter thumbnail
	# this is the thumbnail image that shows on newsletters
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_newsletter' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/newsletter_thumb/images/thumbnails/fullpagearticles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/fullpagearticles%'
	;


	# author teaser thumbnail for full page articles
	# this gets used on that recent stories widget, at least
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_author_teaser' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/fullpagearticles', '/imagecache/author_teaser/images/thumbnails/fullpagearticles')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/fullpagearticles%'
	;


	# for audio

	# feature thumbnail for audio posts
	# this is the larger thumbnail image that shows on section pages from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_middle' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/feature_middle/images/thumbnails/audio')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/audio%'
	;


	# newsletter thumbnail
	# this is the thumbnail image that shows on newsletters
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_newsletter' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/newsletter_thumb/images/thumbnails/audio')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/audio%'
	;


	# author teaser thumbnail for audio
	# this gets used on that recent stories widget, at least
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_author_teaser' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/author_teaser/images/thumbnails/audio')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_audio a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_op_audio_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/audio%'
	;


	# for video

	# feature thumbnail for video posts
	# this is the larger thumbnail image that shows on section pages from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature_middle' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/feature_middle/images/thumbnails/video')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/video%'
	;


	# newsletter thumbnail
	# this is the thumbnail image that shows on newsletters
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_newsletter' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/newsletter_thumb/images/thumbnails/video')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/video%'
	;


	# author teaser thumbnail for video
	# this gets used on that recent stories widget, at least
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_author_teaser' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/author_teaser/images/thumbnails/video')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/video%'
	;


	# there is no /feature/images/thumbnails/slideshow


	# thumbnail for authors themselves
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_author_image_thumbnail' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/author', '/imagecache/author_teaser/images/author')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_author_photo_fid = f.fid
			WHERE f.filepath LIKE '%images/author%'
	;


	# todo: we need to figure out whether and how to handle duplicate meta_keys for the same post
	# but with conflicting values
	# i know that at least sometimes the url is the same; it's being added more than once somehow. this may just not be a problem though.


	# todo: we still need images for events but we don't yet have posts for them :(



# Section 6 - Image Metadata. The order has to come after the images

	# our _wp_imported_metadata field is fixed by the Deserialize Metadata plugin: https://wordpress.org/extend/plugins/deserialize-metadata/

	# there is alt / caption info

	# insert metadata for gallery images - this relates to the image post ID
	# 8/317: this was using the story post id instead of image like it was supposed to. fixed it though i think
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			s.field_op_slideshow_images_nid `post_id`,
			'_wp_imported_metadata' `meta_key`,
			i.field_main_image_data `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_slideshow_images s ON n.nid = s.field_op_slideshow_images_nid
			INNER JOIN `minnpost.drupal`.node n2 ON s.field_op_slideshow_images_nid = n2.nid
			INNER JOIN `minnpost.drupal`.content_field_main_image i ON n2.nid = i.nid
			WHERE i.field_main_image_data IS NOT NULL
			GROUP BY s.field_op_slideshow_images_nid
	;


	# insert metadata for gallery thumbnails - this relates to the image post ID
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
		p.ID `post_id`,
		'_wp_imported_metadata' `meta_key`,
		s.field_op_slideshow_thumb_data `meta_value`
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN `minnpost.drupal`.files f ON p.post_title = f.filename
		INNER JOIN `minnpost.drupal`.content_type_slideshow s ON f.fid = s.field_op_slideshow_thumb_fid
		WHERE s.field_op_slideshow_thumb_data IS NOT NULL
		GROUP BY p.ID
	;


	# insert metadata for slideshow images - this relates to the image post ID
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			s.field_op_slideshow_images_nid `post_id`,
			'_wp_imported_metadata' `meta_key`,
			i.field_main_image_data `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_slideshow_images s ON n.nid = s.field_op_slideshow_images_nid
			INNER JOIN `minnpost.drupal`.node n2 ON s.field_op_slideshow_images_nid = n2.nid
			INNER JOIN `minnpost.drupal`.content_field_main_image i ON n2.nid = i.nid
			WHERE i.field_main_image_data IS NOT NULL
			GROUP BY s.field_op_slideshow_images_nid
	;


	# insert metadata for main images - this relates to the image post ID
	# this now takes vid into account
	# this should cover all the content types that have main images, as long as the images exist
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


	# insert metadata for post thumbnails - this relates to the image post ID
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


	# insert metadata for slideshow post thumbnails - this relates to the image post ID
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


	# custom field for homepage image size for posts
	# this is homepage size metadata, field homepage_image_size, for posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			nid as post_id, '_mp_post_homepage_image_size' as meta_key, field_hp_image_size_value as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_hp_image_size s USING(nid, vid)
			WHERE s.field_hp_image_size_value IS NOT NULL
	;


	# fix homepage size vars to match wordpress image size names
	# these don't really seem to need any vid stuff


	# medium
	UPDATE `minnpost.wordpress`.wp_postmeta
		SET meta_value = 'feature_middle'
		WHERE meta_value = 'medium' AND meta_key = '_mp_post_homepage_image_size'
	;

	# large
	UPDATE `minnpost.wordpress`.wp_postmeta
		SET meta_value = 'feature_large'
		WHERE meta_value = 'large' AND meta_key = '_mp_post_homepage_image_size'
	;


	# excerpt for image posts; this is caption only if it is stored elsewhere
	# the deserialize metadata plugin does not overwrite these values
	# this one does take the vid into account
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.drupal`.node ON wp_posts.ID = node.nid
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions r ON node.vid = r.vid
		SET wp_posts.post_excerpt = r.body
		WHERE wp_posts.post_type = 'attachment' AND r.body != ''
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



# Section 7 - Core Post Metadata. The order doesn't matter here. We can skip this section if we're testing other stuff.

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
	# first we need to delete duplicate meta rows so we can add the constraint
	DELETE t1 FROM `wp_postmeta` t1, `wp_postmeta` t2 WHERE t1.meta_id > t2.meta_id AND t1.post_id = t2.post_id AND t1.meta_key = t2.meta_key AND t1.meta_value = t2.meta_value
	;


	ALTER TABLE `minnpost.wordpress`.wp_postmeta ADD CONSTRAINT temp_newsletter_type UNIQUE (post_id, meta_key, meta_value(255))
	;

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
		SELECT n.nid as post_id, '_mp_newsletter_top_posts_csv' as meta_key, GROUP_CONCAT(t.field_newsletter_top_nid ORDER BY t.delta ASC) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_newsletter_top t USING(nid, vid)
			WHERE t.field_newsletter_top_nid IS NOT NULL
			GROUP BY nid, vid
	;


	# show department on top stories
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			nid `post_id`,
			'_mp_newsletter_show_department_for_top_stories' as meta_key,
			'on' as meta_value
			FROM `minnpost.drupal`.content_type_newsletter n
			WHERE field_top_stories_department_value = 'On'
	;


	# add more stories for all newsletter posts
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_newsletter_more_posts_csv' as meta_key, GROUP_CONCAT(m.field_newsletter_more_nid ORDER BY m.delta ASC) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_newsletter_more m USING(nid, vid)
			WHERE m.field_newsletter_more_nid IS NOT NULL
			GROUP BY nid, vid
	;


	# drop that temporary constraint for newsletter type
	ALTER TABLE `minnpost.wordpress`.wp_postmeta DROP INDEX temp_newsletter_type;



# Section 8 - Categories, their images, text fields, taxonomies, and their relationships to posts. The order doesn't matter here. We can skip this section if we're testing other stuff (we use the old id field to keep stuff together)

	# this category stuff by default breaks because the term ID has already been used - by the tag instead of the category
	# it fails to add the duplicate IDs because Drupal has them in separate tables
	# we fix this by temporarily using a term_id_old field to track the relationships
	# this term_id_old field gets used to assign each category to:
	# 1. its custom text fields
	# 2. its relationships to posts
	# 3. its taxonomy rows


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


	# we need the taxonomy here too because that is how the join works

	# Create taxonomy for each department
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id, 'category', '' FROM wp_terms WHERE term_id_old IS NOT NULL
	;


	# text fields for categories from departments

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


	# temporary table for featured departments with their section id
	CREATE TABLE `wp_featured_terms` (
		`section_id` bigint(20) unsigned NOT NULL,
		`featured_terms` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT ''
	);


	# populate featured departments
	INSERT INTO `minnpost.wordpress`.wp_featured_terms(section_id, featured_terms)
		SELECT cs.field_section_nid as section_nid, GROUP_CONCAT(t.term_id) as featured_terms
			FROM `minnpost.drupal`.node d
			INNER JOIN `minnpost.drupal`.content_field_section cs USING(nid, vid)
			INNER JOIN `minnpost.drupal`.node s ON cs.field_section_nid = s.nid
			INNER JOIN `minnpost.wordpress`.wp_terms t ON t.term_id_old = d.nid
			WHERE d.type = 'department' AND field_section_nid IS NOT NULL
			GROUP BY field_section_nid
			ORDER BY s.title, d.changed
	;


	# we need category images here because we need to have the term_id_old field for the image parent


	# add the image_post_file_id_old field for tracking Drupal file ids
	ALTER TABLE wp_posts ADD image_post_file_id_old BIGINT(20);

	# these image posts also need a temporary term id because they don't have a post parent
	ALTER TABLE wp_posts ADD term_id BIGINT(20);


	# insert main category images as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old, term_id)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			term.term_id `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/department', '/imagecache/feature/images/department')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`,
			term.term_id `term_id`
			FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_main_image i ON i.nid = n.nid AND i.vid = n.vid
			INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
	;

	# insert the id and url as meta fields for the main image for each category
	# each needs the post id for the story
	# _mp_post_main_image_id (the image post id)
	# _mp_post_main_image (full url, at least during the migration phase; it might change when we're uploading natively but who knows)

	# post id for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT
			p.term_id `term_id`,
			'_mp_category_main_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL
	;


	# url for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT
			p.term_id `post_id`,
			'_mp_category_main_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL
	;


	# insert category thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old, term_id)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			'0' `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/department', '/imagecache/thumbnail/images/thumbnails/department')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`,
			term.term_id `term_id`
			FROM wp_term_taxonomy tax
			INNER JOIN wp_terms term ON tax.term_id = term.term_id
			INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
			INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
			INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i ON i.nid = n.nid AND i.vid = n.vid
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
	;


	# insert the id and url as meta fields for the thumbnail image for the category
	# each needs the post id for the item
	# _mp_category_thumbnail_image_id (the image post id)
	# _mp_category_thumbnail_image (full url, at least during the migration phase; it might change when we're uploading natively but who knows)

	# post id for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT
			p.term_id `term_id`,
			'_mp_category_thumbnail_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL
	;


	# url for image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT
			p.term_id `post_id`,
			'_mp_category_thumbnail_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL
	;


	# featured column thumbnail image
	# this is the larger thumbnail image that shows on the top of the homepage from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT DISTINCT
			p.term_id `post_id`,
			'_mp_category_featured_column_image' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE( f.filepath, '/images/thumbnails/department', '/imagecache/featured_column/images/thumbnails/department')) `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL AND f.filepath LIKE '%/images/thumbnails/department%'
	;


	# featured column thumbnail image other path
	# this is the larger thumbnail image that shows on the top of the homepage from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT DISTINCT
			p.term_id `post_id`,
			'_mp_category_featured_column_image' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE( f.filepath, '/images/thumbnails', '/imagecache/featured_column/images/thumbnails')) `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL AND f.filepath LIKE '%/images/thumbnails%'
	;


	# note: featured columns for homepage only is a widget


	# then we can get rid of that temp file id field
	ALTER TABLE wp_posts DROP COLUMN image_post_file_id_old;
	ALTER TABLE wp_posts DROP COLUMN term_id;


	# sections have no images


	# Empty term_id_old values so we can start over with our auto increment and still track for sections
	UPDATE `minnpost.wordpress`.wp_terms SET term_id_old = NULL;


	# get rid of that temporary department table
	DROP TABLE wp_terms_dept;


	# set the department as the primary category for the post, because that is how drupal handles urls
	# in wordpress, this depends on the WP Category Permalink plugin
	# this doesn't really seem to need any vid stuff
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT object_id as post_id, '_category_permalink' as meta_key, CONCAT('a:1:{s:8:"category";', CONCAT('s:', char_length(t.term_id), ':"'), t.term_id, '";}') as meta_value
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
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id, 'category', '' FROM wp_terms WHERE term_id_old IS NOT NULL
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


	# update featured categories so they use the actual section term ids
	UPDATE `minnpost.wordpress`.wp_featured_terms ft JOIN wp_terms t ON t.term_id_old = ft.section_id
		SET ft.section_id = t.term_id
	;


	# put those featured categories into the term meta table
	INSERT IGNORE INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT DISTINCT section_id as term_id, '_mp_category_featured_columns' as meta_key, featured_terms as meta_value
		FROM wp_featured_terms
	;

	# get rid of that temporary featured term table
	DROP TABLE wp_featured_terms;


	# text fields for categories from sections


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
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id, 'category', ''
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


	# CATEGORIES
	# These are NEW categories, not in `minnpost.drupal`. Add as many sets as needed.
	#INSERT IGNORE INTO `minnpost.wordpress`.wp_terms (name, slug)
	#	VALUES
	#	('First Category', 'first-category'),
	#	('Second Category', 'second-category'),
	#	('Third Category', 'third-category')
	#;



# Section 9 - Comments. Order has to be after posts because the post table gets updated. We can skip this section if we're testing other stuff.

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



# Section 10 - User and Author Metadata. Order needs to be after users/authors (#4). We can skip this section if we're testing other stuff.

	# user permissions

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
	# parameter: line 2563 contains the Drupal permission roles that we want to migrate
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


	# user and author text fields

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
	# first we need to delete duplicate meta rows so we can add the constraint
	DELETE t1 FROM `wp_postmeta` t1, `wp_postmeta` t2 WHERE t1.meta_id > t2.meta_id AND t1.post_id = t2.post_id AND t1.meta_key = t2.meta_key AND t1.meta_value = t2.meta_value
	;


	# add a temporary constraint for email addresses so we don't add duplicates
	ALTER TABLE `minnpost.wordpress`.wp_postmeta ADD CONSTRAINT temp_email UNIQUE (post_id, meta_key, meta_value(255))
	;


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
			REPLACE(CONCAT('https://twitter.com/', REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(link.field_link_multiple_url, 'http://www.twitter.com/', ''), 'http://twitter.com/', ''), '@', ''), 'https://twitter.com/', ''), '#%21', ''), '/', '')), 'https://twitter.com/https:www.twitter.com', 'https://twitter.com/') `meta_value`
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


	# in wordpress, the author has a first name/last name and some other fields
	# but we don't store those on the author object in drupal so we don't need to migrate it


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


	# add the excerpt field for the author if we have one
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_author_excerpt' as meta_key,
				t.field_teaser_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
			WHERE t.field_teaser_value IS NOT NULL
	;


	# add the bio field for the author if we have one
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_author_bio' as meta_key,
				r.body `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author author USING (nid, vid)
			WHERE r.body IS NOT NULL and r.body != ''
	;



# Section 11 - Navigational items. The order doesn't matter here but it does have to wait for cron to finish. We can skip this section if we're testing other stuff.

	# Redirects for the Redirection plugin - https://wordpress.org/plugins/redirection/
	# these are from the path_redirect table
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


	# Redirects for the Redirection plugin - https://wordpress.org/plugins/redirection/
	# these are from the url_alias table and these are also necessary, but we have to fix some of the urls because of nesting
	INSERT INTO `minnpost.wordpress`.wp_redirection_items
		(`url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
		SELECT DISTINCT
			CONCAT('/', a.dst) `url`,
			0 `regex`,
			0 `position`,
			1 `last_count`,
			CURRENT_TIMESTAMP() `last_access`,
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
				CONCAT('tag/', substring_index(REPLACE(REPLACE(a.dst, 'category/keywords/', 'tag/'), 'category/minnpost-topic/', 'tag/'), '/', -1))) `action_data`,
			'url' `match_type`,
			'' `title`
			FROM `minnpost.drupal`.url_alias a
			LEFT JOIN `minnpost.wordpress`.wp_posts p ON p.post_name = substring_index(a.dst, '/', -1)
			WHERE p.ID IS NULL AND a.dst NOT LIKE '%author%' AND a.dst NOT LIKE '%department%' AND a.dst NOT LIKE '%section%' AND a.dst != REPLACE(REPLACE(a.dst, 'category/keywords/', 'tag/'), 'category/minnpost-topic/', 'tag/')
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
	);


	# add menus
	# parameter: line 2981 contains the menu types in drupal that we don't want to migrate
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


	# add a menu for featured columns
	INSERT INTO `minnpost.wordpress`.wp_menu
		(name, title, placement)
		VALUES('menu-featured-columns', 'Featured Columns', 'featured_columns');
	;


	# add menu items
	# parameter: line 3023 important parameter to keep out/force some urls because of how they're stored in drupal
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

	
	# insert homepage featured columns
	INSERT INTO `minnpost.wordpress`.wp_menu_items
		(`menu-name`, `menu-item-title`, `menu-item-url`, `menu-item-parent`)
		SELECT 
			'menu-featured-columns' `menu-name`,
			n.title `menu-item-title`,
			substring_index(a.dst, '/', -1) `menu-item-url`,
			NULL `menu-item-parent`
			FROM `minnpost.drupal`.nodequeue_nodes nn
			INNER JOIN `minnpost.drupal`.nodequeue_queue q USING(qid)
			INNER JOIN `minnpost.drupal`.node n USING(nid)
			LEFT OUTER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
			WHERE q.title = 'Homepage Columns' AND n.title != 'The Glean'
			ORDER BY nn.position
	;


	# get rid of those temporary menu tables
	# can't run this until after the migrate-random-things.php task runs twice. once to add parent items, once to add their children if applicable
	DROP TABLE wp_menu;
	DROP TABLE wp_menu_items;



# Section 12 - widgets and ads and sidebar such stuff. The order has to be after posts since that table gets updated. We can skip this section if we're testing other stuff.

	# replace content when necessary

	# use widgets for news by region
	# these numbers change if we have to recreate the widgets. ugh.
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = '<!--break-->
	[widget_instance id="minnpostspills_widget-8"]

	[widget_instance id="minnpostspills_widget-21"]

	[widget_instance id="minnpostspills_widget-11"]

	[widget_instance id="minnpostspills_widget-22"]'
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


	# we have to add a Middle tag manually with is_single conditional


	# have to wait for migrate cron to run before deleting the table


	# get rid of the temporary ad table
	DROP TABLE ads;


	# temporary table for basic html sidebar items and their placement
	CREATE TABLE `wp_sidebars` (
		`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
		`title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
		`url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
		`content` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
		`type` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'custom_html',
		`show_on` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT '',
		`categories` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  		`tags` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
		PRIMARY KEY (`id`)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;


	# put the active sidebar items into that temporary table
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, content, show_on)
		SELECT
            IFNULL(d.field_display_title_value, CONCAT('!', n.title)) as title,
            IF(LENGTH(u.field_url_url)>0, CONCAT(CONCAT(IF(LENGTH(f.filepath)>0, CONCAT('<div class="image">',IFNULL(CONCAT('<a href="/', u.field_url_url, '">'), ''), '<img src="https://www.minnpost.com/', f.filepath, '">', IF(LENGTH(u.field_url_url) > 0, '</a></div>', '</div>')),''), IF(LENGTH(nr.body)>0, nr.body, field_teaser_value)), '<p><a href="/', u.field_url_url, '" class="a-more">More</a></p>'), CONCAT(IF(LENGTH(f.filepath)>0, CONCAT('<div class="image">',IFNULL(CONCAT('<a href="/', u.field_url_url, '">'), ''), '<img src="https://www.minnpost.com/', f.filepath, '">', IF(LENGTH(u.field_url_url) > 0, '</a></div>', '</div>')),''), IF(LENGTH(nr.body)>0, nr.body, REPLACE(field_teaser_value, '[newsletter_embed:dc]', '[newsletter_embed newsletter="dc"]')))) as content,
            IFNULL(i.action_data, GROUP_CONCAT(field_visibility_value)) as show_on
            FROM `minnpost.drupal`.node n
            INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
            INNER JOIN `minnpost.drupal`.content_type_sidebar s USING(nid, vid)
            INNER JOIN `minnpost.drupal`.content_field_visibility v USING(nid, vid)
            LEFT OUTER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
            LEFT OUTER JOIN `minnpost.drupal`.content_field_image_thumbnail i USING(nid, vid)
            LEFT OUTER JOIN `minnpost.drupal`.files f ON i.field_image_thumbnail_fid = f.fid
            LEFT OUTER JOIN `minnpost.drupal`.content_field_url u USING(nid, vid)
            LEFT OUTER JOIN `minnpost.drupal`.content_field_display_title d USING(nid, vid)
            LEFT OUTER JOIN `minnpost.wordpress`.wp_redirection_items i ON v.field_visibility_value = REPLACE(i.url, '/category', 'category')
            WHERE n.status = 1
            GROUP BY nid
            ORDER BY n.status, changed DESC, created DESC
	;


	# update urls
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET show_on = REPLACE(show_on, CONCAT((
			SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				), '/'),
			'')
	;


	# fix the table
	ALTER TABLE `minnpost.wordpress`.wp_sidebars CONVERT TO CHARACTER SET utf8mb4 collate utf8mb4_unicode_ci;


	# Fix image urls in widget content
	# in our case, we use this to make the urls absolute, at least for now
	UPDATE `minnpost.wordpress`.wp_sidebars
	SET content = REPLACE(content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
	;

	
	# manually add a few sidebars
	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`)
		VALUES
			('Featured Columns', NULL, 'menu-featured-columns', 'nav_menu', '<front>', NULL, NULL)
	;

	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`)
		VALUES
			('The Glean', 'glean', '', 'minnpostspills_widget', '<front>', 'glean', NULL)
	;

	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`)
		VALUES
			('Recent Stories', NULL, '', 'rpwe_widget', '!<front>', NULL, NULL)
	;

	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`)
		VALUES
			('', NULL, '', 'popular-widget', '*', NULL, NULL)
	;

	
	# add the active minnpost spills widgets into temporary table
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, url, content, type, show_on, categories, tags)
		SELECT
			n.title as title, u.field_url_url as url, nr.body as content, 'minnpostspills_widget' as type, GROUP_CONCAT(DISTINCT field_visibility_value) as show_on, GROUP_CONCAT(DISTINCT IFNULL(a.dst, d.title)) as categories, GROUP_CONCAT(DISTINCT t.name) as tags
				FROM `minnpost.drupal`.node n
				INNER JOIN `minnpost.drupal`.node_revisions nr ON n.nid = nr.nid and n.vid = nr.vid
				INNER JOIN `minnpost.drupal`.content_type_spill s ON n.nid = s.nid and n.vid = s.vid
				LEFT OUTER JOIN `minnpost.drupal`.term_node tn ON n.nid = tn.nid and n.vid = tn.vid
				LEFT OUTER JOIN `minnpost.drupal`.term_data t ON tn.tid = t.tid
				LEFT OUTER JOIN `minnpost.drupal`.content_field_departments cd ON n.nid = cd.nid and n.vid = cd.vid
				LEFT OUTER JOIN `minnpost.drupal`.node d ON cd.field_departments_nid = d.nid
				LEFT OUTER JOIN `minnpost.drupal`.content_field_visibility v ON n.nid = v.nid and n.vid = v.vid
				LEFT OUTER JOIN `minnpost.drupal`.content_field_url u ON n.nid = u.nid and n.vid = u.vid
				LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', d.nid)
				GROUP BY n.nid
	;


	# add some basic blocks from drupal as widgets
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, url, content, type, show_on, categories, tags)
		SELECT REPLACE(REPLACE(CONCAT('!', info), '!hp_staff', 'MinnPost Staff'), '!hp_donors', 'Thanks to our generous donors') as title, null as url, body as content, 'custom_html' as type, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(delta, 1, 'footer'), 2, 'newsletter-footer'), 3, 'newsletter'), 5, 'newsletter'), 'menu-footer-primary', 'newsletter') as show_on, null as categories, null as tags
			FROM `minnpost.drupal`.blocks
			INNER JOIN `minnpost.drupal`.boxes USING(bid)
			WHERE body NOT LIKE '%gorton%' AND body NOT LIKE '%phase2%' AND delta NOT IN ('admin', 'features', 'menu-footer-secondary', '0')
			ORDER BY delta
	;


	# add the migrated field
	ALTER TABLE `minnpost.wordpress`.wp_sidebars ADD migrated TINYINT(1) DEFAULT 0;


	# after the plugin runs, delete the temporary sidebar table
	DROP TABLE wp_sidebars;



# Section 13 - General WordPress settings.

	










