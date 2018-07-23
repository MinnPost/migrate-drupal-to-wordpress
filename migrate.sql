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

	# make sure encoding is: utf8-unicode (utf8mb4)
	# make sure collation is: utf8mb4_general_ci

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

	# reset the merge value so it can start over with deserializing
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 1
		WHERE option_name = 'merge_serialized_fields_last_row_checked'
	;


	# set the current migrate time to right now
	INSERT INTO `minnpost.wordpress`.wp_options
		(option_name, option_value)
		VALUES('wp_migrate_timestamp', UNIX_TIMESTAMP(NOW()))
		ON DUPLICATE KEY UPDATE option_value = UNIX_TIMESTAMP(NOW())
	;


	# clear the menu ran thing
	DELETE FROM `minnpost.wordpress`.wp_options WHERE option_name = 'menu_check_ran'


	# this is where we stop deleting data to start over



# Section 2 - Core Posts. The order is important here (we use the post ID from Drupal).

	# Posts from Drupal stories
	# Keeps private posts hidden.
	# parameter: line 97 contains the Drupal content types that we want to migrate
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_modified, post_modified_gmt, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			r.body `post_content`,
			n.title `post_title`,
			t.field_teaser_value `post_excerpt`,
			substring_index(a.dst, '/', -1) `post_name`,
			FROM_UNIXTIME(n.changed) `post_modified`,
			CONVERT_TZ(FROM_UNIXTIME(n.changed), 'America/Chicago', 'UTC') `post_modified_gmt`,
			n.type `post_type`,
			IF(n.status = 1, 'publish', 'draft') `post_status`
		FROM `minnpost.drupal`.node n
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions r
			USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a
			ON a.src = CONCAT('node/', n.nid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
		# Add more Drupal content types below if applicable.
		WHERE n.type IN ('article', 'article_full', 'audio', 'event', 'newsletter', 'page', 'partner', 'partner_offer', 'slideshow', 'sponsor', 'video')
	;


	# use [raw shortcodes=1] on post_content where drupal has the raw html format
	UPDATE `minnpost.wordpress`.wp_posts p
		INNER JOIN (
			SELECT DISTINCT
				n.nid as id
				FROM `minnpost.drupal`.node n
				LEFT OUTER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
				WHERE r.format = 5
			) as format on p.ID = format.id
		SET p.post_content = CONCAT('[raw shortcodes=1]', p.post_content, '[/raw]')
	;



	# Fix post type; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-17826
	# Add more Drupal content types below if applicable
	# parameter: line 107 must contain the content types from parameter in line 97 that should be imported as 'posts'
	# newsletter and page should stay as they are
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_type = 'post'
		WHERE post_type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
	;


	# update page hierarchy to include parent when there is one in drupal
	UPDATE `minnpost.wordpress`.wp_posts p
		INNER JOIN (
			SELECT DISTINCT
				n.nid as id,
				substring_index(a2.src, 'node/', -1) as parent_id
				FROM `minnpost.drupal`.node n
				LEFT OUTER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
				LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
				LEFT OUTER JOIN `minnpost.drupal`.url_alias a2 ON a2.dst = substring_index(a.dst, '/', 1)
				WHERE substring_index(a.dst, '/', 1) != substring_index(a.dst, '/', -1) AND n.type = 'page' AND a2.src IS NOT NULL
			) as parent on p.ID = parent.id
		SET p.post_parent = parent.parent_id
	;


	# Fix post type for sponsors
	# This relies on the cr3ativsponsor WordPress plugin
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_type = 'cr3ativsponsor'
		WHERE post_type = 'sponsor'
	;


	# Fix post type for events
	# This relies on the The Events Calendar WordPress plugin
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_type = 'tribe_events'
		WHERE post_type = 'event'
	;


	# insert popups
	# this is a separate query because we only want the bottom popups
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_modified, post_modified_gmt, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			r.body `post_content`,
			n.title `post_title`,
			t.field_teaser_value `post_excerpt`,
			substring_index(a.dst, '/', -1) `post_name`,
			FROM_UNIXTIME(n.changed) `post_modified`,
			CONVERT_TZ(FROM_UNIXTIME(n.changed), 'America/Chicago', 'UTC') `post_modified_gmt`,
			n.type `post_type`,
			IF(n.status = 1, 'publish', 'draft') `post_status`
		FROM `minnpost.drupal`.node n
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions r
			USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a
			ON a.src = CONCAT('node/', n.nid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_mpdm_message m USING(nid, vid)
		# Add more Drupal content types below if applicable.
		WHERE n.type = 'mpdm_message' AND m.field_mpdm_type_value = 'bottom'
	;


	# Fix post type for popups
	# This relies on the Popup Maker WordPress plugin
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_type = 'popup'
		WHERE post_type = 'mpdm_message'
	;


	# create temporary table for popup css
	CREATE TABLE `wp_posts_css` (
	  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	  `post_content_css` longtext NOT NULL,
	  PRIMARY KEY (`ID`)
	);


	# store css in temp table
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts_css
		(id, post_content_css)
		SELECT n.nid as ID, REPLACE(REPLACE(m.field_mpdm_css_value, '.node-type-mpdm_message', '.pum-container'), '.wrapper', '.pum-content') as post_content_css
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_mpdm_message m USING(nid,vid)
			WHERE n.type = 'mpdm_message' and field_mpdm_type_value = 'bottom' AND field_mpdm_css_value IS NOT NULL
	;


	# fix the temp css class hierarchy
	UPDATE wp_posts_css
		SET post_content_css = REPLACE(post_content_css, '.pum-container', '.pum .pum-container')
	;


	# prepend css to the popup body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_css
		ON wp_posts.ID = wp_posts_css.ID
		SET wp_posts.post_content = CONCAT('<style>', wp_posts_css.post_content_css, '</style>', wp_posts.post_content)
	;


	# get rid of that temporary css table
	DROP TABLE wp_posts_css;


	# update comment status where it is disabled
	UPDATE `minnpost.wordpress`.wp_posts p
		JOIN `minnpost.drupal`.node n
		ON p.ID = n.nid
		SET comment_status = 'closed'
		WHERE n.comment = 0 OR n.comment = 1
	;


	## Get Raw HTML content from article_full posts
	# requires the Raw HTML plugin in WP to be enabled
	# wrap it in [raw shortcodes=1][/raw]


	# create temporary table for raw html content
	CREATE TABLE `wp_posts_raw` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_raw` longtext NOT NULL,
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
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, '[raw shortcodes=1]', wp_posts_raw.post_content_raw, '[/raw]')
	;


	# get rid of that temporary raw table
	DROP TABLE wp_posts_raw;


	## Get audio URLs from audio posts
	# Use the Audio format, and the core WordPress handling for audio files
	# this is [audio mp3="source.mp3"]

	# create temporary table for audio content
	CREATE TABLE `wp_posts_audio` (
		`ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`post_content_audio` longtext NOT NULL,
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
		`post_content_video` longtext NOT NULL,
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
		`post_content_gallery` longtext NOT NULL,
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
		`post_content_documentcloud` longtext NOT NULL,
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


	# create temporary table for file attachments that need to be listed because they aren't already in the node body
	CREATE TABLE `wp_posts_attachments` (
	  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	  `post_content_attachment_url` longtext NOT NULL,
	  `post_content_attachment_filename` varchar(256) NOT NULL DEFAULT '',
	  `post_content_attachment_extension` varchar(256) NOT NULL DEFAULT '',
	  `link` longtext NOT NULL,
	  PRIMARY KEY (`ID`)
	);


	# store listed attachments in temp table
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts_attachments
		(id, post_content_attachment_url, post_content_attachment_filename, post_content_attachment_extension)
		SELECT n.nid, CONCAT('/', f.filepath), f.filename, LCASE(SUBSTRING_INDEX(f.filename,'.',-1))
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_files fp USING(nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON fp.field_files_fid = f.fid
			WHERE fp.field_files_fid IS NOT NULL AND r.body NOT LIKE CONCAT('%', REPLACE(REPLACE(REPLACE(f.filepath, ' ', '%20'), '(', '%28'), ')', '%29'), '%') AND field_files_list = 1
	;


	# create the full url for the link
	UPDATE `minnpost.wordpress`.wp_posts_attachments
		SET link = CONCAT('<p><a class="a-icon-link a-icon-link-', post_content_attachment_extension, '" href="', post_content_attachment_url, '">', '<img src="/wp-content/themes/minnpost-largo/assets/img/icons/', post_content_attachment_extension, '.png" alt=""> ', post_content_attachment_filename, '</a></p>')
	;


	# create temporary table for attachment content
	CREATE TABLE `wp_posts_attachments_content` (
	  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
	  `post_content_attachments` longtext NOT NULL,
	  PRIMARY KEY (`ID`)
	);


	# store attachment content in temp table
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts_attachments_content
		(id, post_content_attachments)
		SELECT a.ID, CONCAT('<p><strong>Attached File(s):</strong></p>', '<p>', GROUP_CONCAT(a.link ORDER BY a.ID SEPARATOR '</p>'), '</p>') as attachments
			FROM `minnpost.wordpress`.wp_posts_attachments a
			GROUP BY a.ID
	;


	# append attachment data to the post body
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.wp_posts_attachments_content
		ON wp_posts.ID = wp_posts_attachments_content.ID
		SET wp_posts.post_content = CONCAT(wp_posts.post_content, wp_posts_attachments_content.post_content_attachments)
	;


	# get rid of those temporary attachment tables
	DROP TABLE wp_posts_attachments;
	DROP TABLE wp_posts_attachments_content;


	# Fix image/file urls in post content
	# in our case, we use this to make the urls absolute, at least for now
	# no need for vid stuff
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
	;


	# Fix css urls from Drupal theme in post content
	# these files need to exist in WordPress
	# no need for vid stuff
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '"/sites/default/themes/siteskin/inc/css', '"/wp-content/themes/minnpost-largo/assets/css')
	;
	# relevant files: minnroast.css, sponsor.css

	# except we don't need sponsor.css; it doesn't do anything right now
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '<p><link rel="stylesheet" href="/wp-content/themes/minnpost-largo/assets/css/sponsor.css" /></p>', '')
	;


	# Fix js urls from Drupal theme in post content
	# these files need to exist in WordPress
	# no need for vid stuff
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '"/sites/default/themes/siteskin/inc/js', '"/wp-content/themes/minnpost-largo/assets/js')
	;
	# relevant files: tabs.js


	# Fix ad shortcodes in post content
	# no need for vid stuff
	# replace strings: [ad], [ ad ], [ad:Right1], [ ad:Right1 ]
	# this results in no rows with the above strings in wp_posts
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '[ad]', '[cms_ad]')
	;
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '[ ad ]', '[cms_ad]')
	;
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '[ ad:Right1 ]', '[cms_ad:Right1]')
	;
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '[ad:Right1]', '[cms_ad:Right1]')
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
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<sup></sup>','')
	;
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<sub></sub>','')
	;


	# replace classes when needed
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<div class="credit">','<div class="a-media-meta a-media-credit">')
	;
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content,'<div class="caption">','<div class="a-media-meta a-media-caption">')
	;


	# let's fix the subscribe page so we don't have to recreate it
	UPDATE `minnpost.wordpress`.wp_posts
		SET
			post_author = 1,
			post_content = '[newsletter_embed newsletter="full"]By subscribing, you are agreeing to MinnPost\'s <a href="/terms-of-use">Terms of Use</a>. MinnPost promises not to share your information without your consent. For more information, please see our <a href="/privacy">privacy policy</a>.',
			post_excerpt = '',
			post_name = 'subscribe',
			post_modified = CURRENT_TIMESTAMP(),
			post_status = 'publish'
		WHERE post_title = 'Subscribe' and post_type = 'page'
	;


	# let's fix the staff page so it uses that widget
	UPDATE `minnpost.wordpress`.wp_posts
		SET
			post_content = CONCAT(post_content, '[mp_staff]'),
			post_modified = CURRENT_TIMESTAMP()
		WHERE post_name = 'staff' and post_type = 'page'
	;


	# update javascript in posts
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '<script>', '<script>(function($) {'
	);

	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '<script type="text/javascript">', '<script>(function($) {'
	);

	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '</script>', '}(jQuery));</script>'
	);

	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '>}(jQuery));</script>', '></script>'
	);


	# make sure there are no duplicate raw things
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '[/raw][/raw]', '[/raw]'
	);

	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = REPLACE(post_content, '[raw shortcodes=1][raw shortcodes=1]', '[raw shortcodes=1]'
	);


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



# Section 3 - Tags, Post Formats, and their taxonomies and relationships to posts. The order does not seem to be important here.

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
	# we should put in a spam flag into the Drupal table so we don't have to import all those users. i did add a list of spam user ids from an old saleforce spreadsheet and also from the spam checker app we used to have
	INSERT IGNORE INTO `minnpost.wordpress`.wp_users
		(ID, user_login, user_pass, user_nicename, user_email,
		user_registered, user_activation_key, user_status, display_name)
		SELECT DISTINCT
			u.uid as ID, u.mail as user_login, pass as user_pass, u.name as user_nicename, u.mail as user_email,
			FROM_UNIXTIME(created) as user_registered, '' as user_activation_key, 0 as user_status, u.name as display_name
		FROM `minnpost.drupal`.users u
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND u.uid != 0
		) AND u.uid NOT IN (57041,57042,57043,56232,56294,56291,56256,56260,56765,57031,56433,56439,56443,56646,56950,56964,56915,57232,56234,56872,56249,56266,56267,56314,56317,56184,57070,56917,56371,56180,56384,56982,56851,56500,56512,56270,57104,57174,57188,57213,56574,56250,56832,56681,56709,56216,56526,56734,57034,56634,56645,56427,56683,56898,56925,56928,56934,56940,56949,57177,57184,56277,56279,56200,56280,56222,56374,56389,56394,56209,56284,56287,56289,56297,56398,56300,56320,56326,56306,56468,56411,56417,56448,56504,56246,56251,56562,56575,56655,56665,56218,56495,56231,56237,56583,56590,56593,56262,56263,56252,56669,56761,56823,56854,56880,56355,56364,56661,56790,57084,57032,56521,56656,57092,57164,57165,57201,56425,56385,56423,56435,56792,56815,56797,57111,57180,56450,56265,56626,57100,56847,56187,57228,56720,56829,56799,57003,57081,57173,57181,56726,56533,56370,56686,56702,57054,56544,56576,56578,56323,56303,56328,56633,56958,57132,56788,56255,56283,56796,56993,56196,56293,56390,57005,56697,56496,56592,56436,56442,56723,56658,56461,57109,56773,57087,57124,57172,57192,56878,56748,56992,56775,56253,56393,57076,56298,56704,56382,56931,56794,56182,56789,57204,57058,56749,57050,57183,56418,56760,56244,56946,56235,56419,57106,56649,56860,57147,56330,56942,56966,56363,56827,56236,56659,56401,56192,56195,56204,56288,56203,56882,56819,57211,56587,56540,56864,56598,56212,56313,56640,57226,56853,56943,56594,56302,56400,56558,56727,56305,57055,57171,56413,56923,56956,56837,56859,56894,56900,56919,56920,56973,56813,56865,56870,56420,56214,56278,56754,56914,56308,56810,56343,56650,56664,56695,56630,56991,56824,56875,56191,56693,57057,57083,57101,57116,56337,56354,57117,57134,57189,57193,57200,56951,57015,57027,56600,56776,56791,56274,56674,56731,56798,56197,56221,56339,56227,56273,56217,56219,56349,56299,56351,56186,56272,56275,56207,56627,56565,56404,56309,56325,56464,56434,56453,56456,56301,56473,56547,56564,56571,56596,56607,56635,56653,56316,56886,56906,56652,56426,56909,56945,56952,56961,56963,56965,56981,56336,57144,57185,56475,56539,57008,57178,56930,56654,57088,57110,56378,56457,56916,57011,56329,56572,56591,56614,56399,56410,57073,57044,56694,56657,56312,57148,56715,56763,56707,56402,56438,56801,57219,56814,56821,56826,56660,56670,56676,56680,56687,56685,56730,56703,56740,56696,56834,56787,57012,57014,57028,57030,57062,57064,57069,56739,56929,56975,56984,56816,57123,57157,56927,56712,56932,57114,57156,56987,57155,57102,57071,57108,56902,56843,56770,57136,57072,57131,57207,57039,56241,56264,56268,56226,56185,56406,56522,56545,56206,56223,56315,56639,56403,56441,56506,56689,56699,56701,56743,56747,56779,56668,56307,56476,56638,56242,56714,56356,56208,56271,56809,56979,56340,56857,56970,56602,56304,56472,56470,56261,56606,56181,56269,56960,57176,56202,56977,56995,57096,56379,56822,56746,56828,56793,56903,57004,57029,56724,56974,56243,56357,56447,56492,56764,56454,56580,56582,56615,56690,56613,56647,56805,56554,56610,56643,56700,56780,56812,57040,56322,56933,56944,57006,57019,56228,57052,57112,57138,57146,57221,56688,56679,56430,56342,56412,57159,56671,56716,56624,56455,56989,56286,56889,56281,56939,56768,56901,56969,56972,56705,56603,56616,57060,57089,57115,56752,56784,56677,56538,57068,57233,56233,56597,56733,56535,57067,56573,56855,56774,56368,56437,56911,56957,56637,56893,56490,56586,56215,56290,56608,57010,57152,56347,56358,56361,56636,57036,57056,57229,56678,56759,56190,56245,56941,56362,56737,56388,56484,56831,57139,56684,56397,56474,56907,56585,56625,56373,56445,56519,57105,56641,56523,56682,56750,56783,56833,56842,56845,56884,56899,56662,56850,56862,56866,56869,57231,56896,56983,56691,56240,56408,57186,57217,56183,56211,56229,56254,56258,56285,56295,56755,56428,56205,56725,56210,56745,56785,56431,56220,56372,56381,56416,56432,56451,56460,56479,56198,56201,56213,56247,56507,56248,56257,56259,56276,56534,56310,56311,56321,56333,56350,56367,56599,56612,56735,56998,56365,57047,57097,56424,56873,56644,56877,56976,56918,57120,56324,56839,56386,56756,56629,57166,56818,56675,56282,56296,56632,57107,57212,56642,56778,56331,56631,56225,56953,56692,57140,56563,56508,56415,56335,56994,57020,57098,57203,56988,57037,57143,57160,56199,56962,56605,56710,56728,56836,57077,57091,57187,56510,56753,57059,57033,57035,57049,57094,56465,56978,56721,56835,56879,56651,56663,56947,56999,57051,56376,57017,57022,56769,57170,56421,56380,57095,56922,56377,57078,57133,56757,56744,56392,57158,57113,56595,56820,56407,56604,57205,57191,56409,56383,56405,56440,56449,56444,56429,56422,56446,56511,57227,56609,56802,56825,57129,57137,56895,56667,56858,56885,56706,56926,57119,57161,57075,57086,57135,57162,57167,57168,56648,56491,56856,56997,57079,56527,57220,56971,57093,56493,56841,56936,57208,56959,56968,56849,57046,56771,56751,56786,56549,56795,56811,56766,56781,56762,56817,56800,56838,56804,56830,56808,56803,56840,56846,56844,56955,56921,56881,56935,56863,57009,57179,57202,57210,57021,57118,57141,57025,57061,57125,56908,57099,57169,57149,56848,57128,57552,57555,57878,57898,57908,57851,57885,57902,57913,57915,57935,57854,58014,58027,58000,57955,58013,57904,57907,57976,57942,57933,57871,57975,57864,57941,57958,57880,58016,58069,58077,58081,58064,57877,58053,57928,58033,57993,58114,57989,57936,57960,58104,57911,57950,57948,57886,57897,57945,57910,57919,57923,57927,57860,57946,58629,58256,58384,58543,58399,58304,58530,58262,58264,58305,58755,58238,58245,58466,58505,58663,58295,58167,58210,58234,58267,58631,58576,58169,58212,58659,58565,58223,58164,58184,58188,58301,58442,58508,58649,58189,58350,58181,58191,58204,58260,58313,58205,58679,58325,58368,58369,58172,58319,58357,58711,58279,58375,58427,58437,58438,58439,58458,58504,58534,58728,58284,58421,58541,58590,58597,58601,58742,58744,58745,58644,58694,58657,58705,58715,58721,58756,57538,57543,57475,57287,57298,57307,57326,57350,57365,57508,57383,57389,57409,57430,57276,57253,57257,57258,57283,57284,57290,57299,57319,57295,57312,57323,57436,57280,57496,57371,57243,57390,57413,57491,57260,57322,57308,57343,57302,57541,57320,57529,57294,57414,57424,57259,57292,57304,57351,57448,57456,57486,57495,57499,57358,57392,57286,57338,57318,57296,57327,57321,57332,57316,57551,58117,58116,58122,58142,58213,58277,58684,58374,58495,58522,58591,58602,58688,58690,58229,58293,58360,58491,58701,58151,58740,58762,58525,58366,58494,58603,58150,58227,58283,58347,58409,58455,58515,58639,58641,58217,58342,58546,58669,58120,58124,58731,58757,58751,58765,58763,58767,57333,57300,57315,57337,58334,58420,58290,58130,58354,58249,58274,58382,58446,58448,58395,58560,58470,58606,58224,58539,58596,58153,58335,58540,58180,58239,58315,58340,58159,58341,58578,58586,58331,58611,58263,58135,58198,58265,58567,58570,58623,58136,58144,58145,58183,58194,58216,58362,58405,58441,58445,58453,58549,58179,58192,58193,58220,58253,58297,58346,58394,58410,58242,58255,58568,58415,58426,58434,58443,58478,58182,58558,58583,58480,58484,58512,58359,58385,58339,58465,58128,58640,58521,58582,58201,58656,58764,58152,58197,58243,58257,58271,58454,58475,58723,58725,58276,58118,58378,58585,58632,58332,58503,58545,58685,58670,58471,58221,58706,58741,58717,58381,58450,58490,58492,58510,58513,58536,58587,58610,58622,58132,58673,58146,58175,58185,58317,58323,58330,58403,58412,58468,58483,58593,58270,58517,58535,58564,58379,58551,58599,58720,58380,58119,58627,58668,58618,58648,58683,58268,58436,58462,58553,58129,58236,58363,58373,58413,58713,58186,58209,58559,58609,58248,58547,58485,58661,58344,58397,58127,58141,58600,58630,58160,58162,58211,58324,58612,58202,58282,58285,58487,58556,58311,58327,58337,58377,58386,58768,58716,58708,58710,58719,58387,58400,58406,58419,58452,58457,58658,58133,58139,58166,58237,58320,58372,58422,58467,58474,58479,58481,58489,58499,58509,58472,58633,58519,58524,58526,58533,58548,58579,58190,58195,58261,58280,58664,58666,58214,58171,58207,58254,58123,58702,58761,58423,58554,58727,58367,58411,58518,58314,58376,58388,58168,58628,58674,58203,58233,58244,58272,58343,58393,58404,58464,58486,58501,58743,58747,58507,58528,58532,58577,58581,58592,58613,58625,58766,58647,58247,58328,58126,58364,58407,58428,58456,58482,58488,58718,58206,58307,58322,58511,58520,58552,58562,58569,58571,58594,58598,58605,58620,58635,58176,58199,58318,58414,58418,58429,58174,58219,58246,58321,57314,57249,57335,57797,57819,57832,57818,58769,58771,58770,58772,57867,57895,57914,57896,57879,57890,57957,58045,57921,57924,57939,57998,58001,57861,57967,57894,57974,57952,59162,57275,57339,57361,57366,57677,57839,57593,57856,57630,57707,57808,57576,57795,57625,57632,57711,57736,57751,57762,57778,57781,57614,57641,57597,57875,57900,57752,57796,57559,57637,57811,57688,57709,57829,57773,57810,57563,57579,57585,57587,57589,57607,57621,57653,57657,57717,57722,57730,57755,57766,57737,57745,57647,57775,57777,57783,57813,57840,57841,57866,57918,57634,57658,57565,57567,57564,57850,57855,57887,57891,57852,57685,57705,57712,57807,57669,57683,57626,57724,57790,57846,57610,57616,57800,57731,57753,57771,57835,57596,57648,57759,57663,57830,57689,57620,57569,57739,57761,57786,57793,57652,57656,57806,57820,57821,57824,57590,57598,57613,57700,57704,57713,57679,57582,57591,57664,57804,57809,57814,57561,57678,57680,57716,57577,57644,57726,57729,57735,57760,57805,57601,57609,57618,57845,57767,57770,57776,57779,57785,57787,57794,57674,57696,57699,57728,57754,57757,57772,57798,57666,57815,57668,57568,57694,57554,58775,58774,58925,58926,58918,58773,58808,59052,58780,58846,58853,58929,58852,58865,58891,58942,58903,58837,59047,58805,58886,58776,59225,59173,59108,59169,58807,59085,59062,58820,58783,59202,59275,59032,59106,58862,59069,59158,59236,59251,59285,59250,59319,59018,58962,58991,59292,59298,58836,58963,59008,58882,58938,58817,59002,59092,58905,59056,59199,59244,58990,59249,58832,58841,59121,59046,59306,59307,59308,59125,58810,59330,59167,59257,58964,59022,58845,58996,58928,58893,58924,59153,59095,58900,59049,59156,59060,59063,58997,59088,59105,59026,58992,59409,59446,59448,59456,59458,59459,59277,59299,59300,59465,58867,58881,58911,58959,59093,59157,59091,58879,58892,59033,59132,59134,59171,59303,59224,59290,59542,59584,59640,59737,58816,59235,58791,59510,59512,59518,59551,59555,59556,59579,59580,59585,59601,59605,59637,58954,58935,58993,59013,59747,59130,59484,59166,59361,58904,58785,58922,59057,58778,58793,58976,59035,59065,59096,59113,58854,58979,58972,58930,58794,58888,59059,58872,58944,59048,59128,58977,59061,59068,59147,59149,59172,58923,59072,59115,59120,59034,58802,58932,58941,59692,58781,59099,59117,59479,59138,59146,59081,59124,59398,59213,59254,59283,58855,59267,58825,58849,58877,59412,59003,59367,59470,59566,59010,59282,59604,59617,59664,59685,59161,59015,58871,58958,59038,59045,59122,59019,58916,59246,59253,59145,59154,58915,58792,58797,58866,58787,58859,58831,58968,58946,58931,58833,58869,58912,58917,58949,58966,58919,58939,58940,58806,58874,58937,58857,58788,58953,58913,58870,58811,58914,58943,58884,58812,58969,58873,58876,58899,58936,58835,59603,59717,59404,58838,58843,58844,59135,58782,59698,59011,59040,58809,58848,59611,59629,59630,59701,59226,58901,59189,59191,58955,59097,59116,58813,59356,59228,59316,59165,59393,59399,59407,59348,59449,59472,59243,59266,59273,59297,59320,59433,59576,59577,59621,59631,59473,59178,59427,59541,59723,59752,59713,59313,58973,58880,59410,58803,59653,59177,58927,59233,59287,59686,59704,58908,58804,58829,58851,58890,58921,58948,59485,59571,59595,59667,59207,59229,59252,59284,59272,59562,59593,59607,59639,59774,59364,59086,59100,59483,59506,58982,59051,58863,58889,58971,59016,59463,59744,59756,58947,58952,59387,59563,59709,59741,59434,59336,59524,59583,59083,59137,59140,59025,59622,59444,59020,59324,58885,58902,58839,58878,59098,59520,59560,59260,59291,59163,59293,59217,59492,59582,59749,59321,59327,59548,59641,59087,59079,59634,59660,59718,59732,59736,59497,59522,59540,59715,59021,59037,59109,59136,58974,59350,59028,59360,58981,59654,59762,58895,58909,58985,59029,58883,58887,59370,59511,59515,59609,59222,59259,59247,59201,59206,58847,58945,58960,58840,58957,58965,59438,59255,58796,59007,58821,58910,59082,59565,59598,59648,59696,59064,58779,58795,59074,59152,59053,59071,59119,59212,59755,59168,59131,59101,58967,59278,58842,59110,59196,59428,59150,58988,59608,59636,59729,59773,59075,59383,59332,59440,59450,59481,59080,58984,59561,59612,59649,59687,59714,59725,59772,59674,59775,59027,59310,59055,58818,59205,58850,58856,58861,58864,59023,59683,58933,58934,59286,59089,59312,58978,59372,59376,59504,58799,59036,59521,59527,59552,59574,59632,59666,58777,59445,59005,59039,59672,59678,59721,59740,59753,59757,59770,59185,59402,59314,59118,59466,59597,59627,59716,59141,59159,59170,58906,58920,58801,58819,58827,58830,58786,58994,59221,59269,59378,59530,59591,59126,59070,58789,58790,59702,59734,59661,58980,58970,59143,59012,59066,59014,59218,59261,59238,59160,59215,59264,58998,59148,59216,59104,59050,59111,59024,59112,59288,59296,59030,59464,59488,59559,59656,59671,59703,59754,59778,59335,59043,58987,59347,59349,59268,59123,59203,59417,59435,59182,59197,59208,59044,59219,59490,59328,59359,59139,59042,59200,59220,59231,59586,59615,59659,59017,59031,59707,59739,59256,59677,59271,59204,59209,59214,59058,59090,58983,58989,59333,59239,58986,59006,59000,59001,58975,59133,59223,59129,59067,59084,59413,59415,59426,59432,59441,59517,59536,59587,59589,59195,59397,59690,59280,59727,59728,59054,59289,59311,59232,59455,59679,59334,59345,58999,59076,59041,59489,59681,59763,59487,59516,59537,59544,59073,59102,59107,59179,59382,59194,59777,59317,59371,59388,59374,59502,59543,59711,59353,59662,59127,59078,59187,59077,59295,59528,59414,59546,59174,59210,59281,59103,59276,59304,59188,59114,59362,59722,59509,59248,59263,59708,59712,59452,59363,59469,59242,59279,59144,59183,59186,59619,59192,59193,59670,59305,59211,59237,59262,59265,59318,59501,59673,59493,59495,59505,59408,59486,59532,59443,59726,59771,59454,59457,59421,59423,59424,59594,59645,59745,59340,59375,59425,59535,59644,59694,59151,59477,59181,59385,59400,59422,59573,59758,59270,59331,59175,59176,59198,59230,59315,59322,59323,59326,59329,59240,59241,59258,59274,59294,59301,57293,57306,57398,57503,57251,57500,57511,57311,57305,57373,57364,57443,57444,57239,57250,57254,57285,57309,57604,57746,57802,57812,57686,57719,57827,57834,57600,57608,57612,57659,57822,57823,57828,57838,57849,57799,57825,57628,57655,57661,57848,57676,57791,57638,57764,57670,57662,57703,57624,57727,57733,57578,57836,57837,57843,57710,57742,57831,57749,57768,57789,59494,59507,59529,59549,59568,59588,59391,59394,59482,59381,59419,59471,59358,59475,59389,59337,59430,59462,59613,59623,59655,59684,59691,59695,59575,59624,59675,59759,59500,59539,59420,59355,59338,59663,59689,59468,59738,59761,59635,59705,59731,59764,59405,59429,59461,59625,59646,59697,59553,59558,59592,59616,59633,59352,59478,59519,59550,59628,59642,59341,59396,59742,59351,59368,59572,59765,59401,59602,59658,59392,59554,59647,59431,59498,59508,59513,59581,59751,59693,59436,59442,59766,59439,59533,59569,59578,59614,59638,59665,59451,59491,59447,59476,59460,59545,59590,59344,59357,59600,59606,59620,59626,59650,59652,59699,59710,59743,59346,59406,59467,59570,59390,59437,59531,59534,59557,59599,59706,59453,59733,59416,59342,59748,59618,59643,59768,59651,59386,59403,59668,59379,59657,59719,59596,59669,59503,59676,59343,59474,59496,59499,59767,59395,59547,59730,59567,59776,59610,59700,59750,59735,59769,59760,59720,59746,57357,57368,57381,57385,57282,57457,57462,57468,57278,57487,57270,57346,57369,57380,57281,57297,57324,57240,57272,57255,57525,57533,57269,57329,57252,57334,57331,57279,57291,57374,57439,57341,57400,57421,57433,57434,57244,57277,57301,57330,57328,57340,57242,57256,57271,57273,57313,57556,57247,57387,57803,57817,57454,57303,57325,57356,57758,57844,57288,57317,57459,57464,57482,57411,57423,57367,57238,57575,57619,57627,57633,57635,57646,57458,57370,57595,57473,57651,57642,57274,57310,57784,57492,57546,57497,57375,57432,57416,57427,57507,57528,57510,57899,57926,58037,58048,58072,58043,58054,58060,57916,57934,57922,58022,58025,58032,58066,58075,57865,57917,57901,58011,57889,58088,57909,57951,58047,57876,57858,57961,57963,58035,58006,58023,58093,58068,57953,57932,57892,57920,57853,57930,57862,57882,57937,57868,57903,57943,57869,57883,57355,57363,57378,57437,57447,57451,57345,57422,57449,57342,57396,57412,57453,57417,57419,57429,57493,57359,57404,57599,57623,57581,57603,57611,57617,57629,57660,57654,57571,57560,57684,57570,57706,57562,57769,57650,57584,57602,57583,57622,57763,57718,57594,57682,57732,57833,57673,57667,57572,57580,57592,57631,57640,57643,57782,57765,57649,57702,57842,57847,57588,57639,57645,57665,57714,57721,57723,57725,57734,57744,57748,57756,57774,57780,57788,57792,57874,57929,57944,57938,57925,57931,57940,58020,58030,58091,57997,58044,57983,57996,58089,58105,57992,58009,58106,58061,58080,58083,58097,57956,57978,57469,57514,57517,57501,57452,57477,57353,57428,57435,57506,57527,57450,57408,57431,57442,57446,57377,57544,57348,57391,57402,57498,57401,57539,57347,57465,57530,57505,57521,57372,57379,57393,57502,57425,57440,57472,57418,57362,57524,57384,57470,57485,58070,58003,58125,58079,58029,57972,57949,58108,58115,57984,57977,57971,57964,57970,58071,58073,58076,58085,58090,58040,58099,58005,58008,58100,58021,57954,58019,57990,58055,57476,57488,57494,57512,57513,57349,57354,57360,57386,57483,57489,57523,57426,57420,57445,57395,57455,57467,57516,57403,57405,57415,57474,58024,58065,57980,58015,58007,57981,57965,57987,58004,58046,58107,58111,57973,57985,57994,57959,58026,58028,57969,58018,58050,58063,57966,58039,58002,58049,58084,58031,58082,58010,58094,57999,58012,58078,58052,58042,58121,58036,58074,58041,58067,58110,58051,58057,58113,58058,58096,58098,59896,59833,59838,59872,59903,59887,59810,59889,59782,59779,59813,59830,59845,59870,59871,59880,59844,59882,59883,59854,59837,59840,57471,57438,57394,57397,57534,57460,57466,57490,57509,57481,57515,57518,57461,57537,57463,57542,57545,57522,57532,57519,58034,58102,58062,58109,58112,58059,58092,58101,58103,58095,58138,58643,58389,58604,58616,58170,58391,58392,58402,58626,58638,58158,58681,58266,58302,58356,58383,58401,58408,58451,58502,58700,58288,58349,58469,58699,58709,58329,58760,58177,58637,58154,58178,58240,58309,58355,58361,58147,58733,58208,58352,58572,58222,58477,58555,58228,58430,58252,58165,58143,58299,58303,58516,58538,58561,58759,58691,58218,58497,58514,58608,58432,58435,58444,58449,58476,58523,58529,58563,58650,58542,58573,58734,58642,58667,58589,58607,58614,58692,58695,58697,58749,58187,58225,58574,58617,58619,58712,58722,58754,58729,58738,58739,58131,58155,58215,58231,58235,58250,58258,58748,58758,58291,58300,58370,58660,58687,58714,58753,58196,58134,58149,58173,58292,58308,58310,58735,58200,58296,58336,58424,58156,58287,58433,58527,58531,58251,58286,58550,58566,58580,58137,58230,58241,58275,58584,58588,58726,58636,58294,58345,58358,58416,58440,58473,58498,58537,58645,59852,59851,59863,59892,59885,59891,59814,59897,59884,59806,59820,59828,59831,59842,59849,59877,59900,59908,59874,59904,59781,59784,59822,59869,59819,59797,59848,59835,59909,59914,59912,59787,59790,59817,59827,59876,57548,57549,57550,58390,58675,58693,58351,58353,58371,58417,58463,58595,58269,58634,58703,58707,58148,58621,58312,58431,58460,58500,58732,58736,58750,58752,58278,58461,58506,58544,58557,58615,58140,58161,58163,58232,58273,58662,58289,58306,58646,57547,56852,56867,56868,56876,56874,56871,56888,56890,56905,56913,56910,56938,56985,56948,56954,56967,56986,56980,57000,57002,56990,57001,56996,57018,57013,57122,57085,57127,57103,57063,57080,57082,57074,57066,57151,57090,57145,57163,57182,57218,57153,57121,57190,57154,57175,59879,59951,59919,59865,59867,59873,59858,59906,59783,59856,59895,59924,59815,59818,59800,59829,59834,59839,59925,59942,59917,59881,59798,59898,59947,59860,59941,59862,59875,59886,59910,59920,59929,59857,59878,59808,59788,59792,59899,59901,59905,59832,59888,59945,59793,59861,59789,59907,59866,59855,59959,59930,59966,59803,59956,59933,59809,59916,59805,59864,59894,59902,59911,59967,59868,59823,59893,59826,59836,59791,59850,59785,59932,59812,59816,59821,59824,59796,59890,59927,59846,59935,59853,59944,59965,59952,59953,59963,59958,59923,59934,59926,59949,59957,59960,59968,59948,59915,59928,59937,59954,59922,59936,59938,59964,59961,59962) AND u.uid NOT IN (
			SELECT uid
				FROM `minnpost.drupal`.users u
				LEFT OUTER JOIN `minnpost.drupal`.salesforce_object_map m ON u.uid = m.oid
				WHERE m.oid is null AND uid IN (60285,60298,59577,61358,61148,59647,59628,60722,45479,53079,23460,30499,47539,25988,57297,19061,39195,60356,50249,19733,59667,59660,59661,26583,26161,26464,26552,26485,26503,26478,26537,26074,26146,26082,26111,26542,26540,26504,20936,42558,42303,45420,45266,20773,56424,56383,37922,60563,24041,20325,33001,19731,43865,33214,31078,51638,51927,45703,45749,53679,62827,42094,33099,33092,62839,41108,43866,32323,19741,56737,55288,30892,35082,31383,43850,34448,53247,39578,31815,62856,45488,63008,46026,53707,60604,61309,61701,57522,32700,19490,31688,41380,43883,31151,60907,47901,45827,47187,47213,53622,42290,54365,27832,52675,41200,49788,55896,39345,53552,34938,46424,33295,47037,48586,36072,35231,58048,56750,39642,36217,52157,52365,46521,37686,49043,43267,50158,58013,58257,58196,58310,58215,37587,56722,36648,50345,56431,36203,35155,40038,56607,44037,36484,53966,38954,50992,19319,60946,54140,47506,48012,47340,35320,43291,54350,37554,33189,35696,63469,48282,61986,47691,40973,54261,33679,59829,41145,58503,38171,44629,63834,60881,52943,36744,58243,31277,46685,53950,51773,58982,45614,53210,30917,63474,45579,52910,44251,42009,47659,38459,44905,48049,35813,56997,38928,62821,57013,37902,57203,28993,56313,56875,58054,30877,43261,48839,37163,48985,54792,47493,41932,58970,62184,48914,58528,58576,52869,42449,36208,48086,39453,44503,36455,30380,41536,37160,52588,51821,60843,42777,46433,62911,59982,50739,36846,34871,56549,43782,54055,59909,57390,62865,54241,35871,50370,36499,52960,19033,39383,36919,42137,57633,56205,42734,35464,44128,50877,35116,60803,58499,54809,40733,47915,31988,51329,48243,43877,36086,63092,44297,61210,49531,48807,46274,59404,59436,31177,37525,54330,45714,56605,31100,58794,57432,63428,47942,36088,49542,33666,42318,49958,55495,43030,36497,58373,48111,53334,60555,44972,54615,36427,62673,42967,32278,57683,63233,35723,38898,53631,57984,58727,60408,43970,41123,58551,31558,54642,45555,62904,61162,59077,43173,34277,52457,40744,56259,62814,39404,60703,29421,60304,35041,32595,37614,19524,43128,33767,29347,40330,44218,31363,44650,51950,29545,33762,51689,19133,43715,56995,46841,34018,32312,30788,51707,34063,48806,56419,31955,27536,59885,57578,48324,60182,51603,59662,42197,54652,54649,32673,35002,45660,47122,63717,56214,34055,25304,42138,57807,22542,62242,53336,48847,32114,51520,34960,35376,50254,63287,44013,33826,39543,46033,42206,60550,59210,31380,47956,54502,58612,24081,39562,63752,61139,56798,39249,31830,53302,47893,45507,44125,36900,44559,36832,59545,34410,31224,32142,43300,63099,45926,39086,31928,48900,56415,51921,35340,58643,59823,61868,47705,39751,52573,62190,61356,28033,57495,54380,63038,41373,42169,29603,52724,38122,35225,41648,36751,59450,56110,43425,36441,57717,61750,31891,61185,40708,37638,45912,48590,57637,61572,61066,48779,50001,31388,61823,45884,54813,54524,57700,34796,40761,63095,42593,62880,57277,54430,58842,52730,54563,33534,62316,47903,56726,57644,40003,42127,51878,53241,59793,43157,41946,55254,63171,34933,32039,62965,45297,43875,39076,61815,42461,33802,55173,41713,27554,61302,47892,58146,37820,45535,52631,60289,50038,59733,59785,61261,53768,33505,35820,47874,63186,43084,33963,55555,38237,48610,30624,41797,54479,57083,47480,58843,53504,50817,31216,41180,49116,52357,50368,51833,47162,38267,52427,32187,40320,62799,58592,31417,59933,63296,44964,38430,33171,35044,30649,60247,36987,44448,59078,45233,63004,52647,47403,44224,18995,32149,34719,57650,31217,59323,48856,56437,52042,32162,57849,42248,64925,60840,57587,59348,54605,47123,62150,58060,58520,53456,53562,60197,52445,59329,53127,41247,31185,53738,38922,45863,42487,59301,38306,61732,19514,58902,32224,59516,36881,43858,36928,54863,60382,38923,50891,50781,38737,61576,52480,40805,62365,35800,55321,51193,62847,45374,38550,26455,34971,60430,41401,43266,39331,45812,47838,40672,41727,50995,59034,19105,62007,56612,35097,45220,60145,33031,19392,62895,35571,52771,61560,44433,60286,63165,38119,38014,61349,49407,31758,40622,55611,51294,34426,59613,39657,60818,63133,52180,50384,41969,56899,55454,40987,53937,46765,50805,41444,60253,41181,42747,38815,51631,61352,62079,61694,61760,58448,58994,57102,56664,30867,49571,59985,19160,37648,42951,57572,48812,59957,60973,41293,41508,52110,44343,53251,49240,54653,60435,51676,45763,63865,62903,50352,51539,30192,52403,62640,51272,46597,36571,50851,35352,58882,52613,45531,30514,39587,47231,46124,57813,41159,42154,52200,63118,54878,41340,46066,61417,57440,50461,54503,51494,30159,48412,52388,61810,60045,40606,51258,48977,51845,54543,19019,54428,59281,31439,62046,50334,60264,52401,39792,32522,46494,34204,37739,52448,52434,43736,60106,28121,60991,54880,57866,46646,49724,59501,45815,51211,37016,29510,61722,53189,57075,59228,62646,62130,42751,33493,40093,57027,51381,56707,51674,46080,34444,37028,62573,53026,57099,36123,54500,34844,39514,39173,62017,62489,62303,34802,52758,38356,45980,34843,61919,56299,56363,56323,56479,56465,56378,62846,46836,56427,38204,56307,50035,31879,45865,19108,55469,30469,60121,27682,27749,34039,31911,55647,51838,44521,54012,44544,62539,52117,51563,54512,58221,33631,35083,31541,61382,53962,44891,45828,41486,35360,40122,38574,61242,44943,58778,57818,62917,51940,34303,38714,51793,47022,60141,45665,37461,53907,59327,49874,63167,35475,61200,25263,61538,34326,51711,34611,31968,54522,63105,35918,51493,35413,32013,31669,58100,53436,48787,53215,39522,42613,47776,39154,19015,56495,56368,56381,56423,56322,56370,56490,49455,39554,56296,56379,56434,56306,56476,59654,45177,59908,53350,50179,59532,33769,57652,35323,46053,30679,59927,61473,57086,39646,57622,50989,47431,44400,56989,48117,43284,19237,28619,56221,60748,50182,41980,45190,50530,61860,38261,39423,40983,61161,58735,34649,38708,59402,41868,50186,45791,42356,51514,52953,52429,57287,31266,60609,44477,47417,42865,53870,30652,59983,56838,56271,29881,49115,58454,61288,56099,58199,54098,35478,53676,50528,51008,45671,44327,35143,40914,44329,41774,59006,54875,63210,47000,45962,33818,31900,56328,36470,51677,57315,34241,43975,56702,54304,52933,29174,39859,33756,50649,55912,19064,46764,35706,37122,24232,39268,53503,60091,58848,48889,46253,59969,35484,60778,33730,39471,41516,43493,47948,51683,43754,57138,39630,35120,46643,61126,53410,33773,39277,33968,25705,64426,47245,33541,45800,61291,64078,34567,41733,46859,51411,52781,43929,43027,36801,58444,41917,42649,41144,56828,56651,63011,36039,33564,52782,39484,40607,30285,59317,35468,41063,29273,38185,29684,45336,41649,62908,46098,34139,34161,60755,59326,52009,32232,41485,56433,27885,42185,42267,54490,35461,29006,46130,62979,62091,54689,27940,40782,56969,19287,49530,34716,38011,30672,51983,60643,34762,62069,51378,56636,38893,34452,38039,45040,39658,34924,36377,28332,57326,56285,60828,52218,36947,31531,23486,53343,52164,27734,37491,63552,46414,63162,37277,26291,53694,28693,53452,50079,62841,58290,45472,35455,36015,61082,64737,50476,51235,34692,34619,41672,40515,50971,28002,38244,34694,52984,52754,47923,40763,47441,39916,49933,54557,53613,42699,31640,46472,52792,52679,36739,43766,49630,46153,45215,50012,52640,47279,56233,38909,51191,60902,50598,44528,45689,46108,37637,61160,57060,52968,38041,60804,57896,36110,61395,31357,47222,47099,52586,60125,34903,47666,31049,34897,39733,53535,40725,58366,57193,52367,38043,45985,37672,30921,58155,44577,62076,38629,34885,57749,56302,45860,41408,54806,51913,61208,50430,49254,44548,60293,61786,49748,36259,56809,58212,42074,41223,49988,31460,58164,49932,51360,49005,61188,52344,35789,54063,37407,47355,58646,31096,37605,60984,61504,25412,40181,41263,33187,44269,64427,56455,34497,53257,47136,56473,30914,33052,54132,36145,41812,36019,57512,40628,32816,46975,52600,49476,52253,43542,44265,59676,51160,38358,59586,47619,51503,56827,61408,37477,30816,58463,46447,51058,60357,61276,43690,50206,41219,43543,53108,45895,38491,61256,36303,49606,49229,49272,49720,50056,51487,49616,39199,57666,41767,50128,47741,31611,62282,41441,34711,60962,28473,36956,35622,32189,31984,43341,40154,43465,32182,45904,53887,60837,41188,47798,40777,58352,31422,38440,56372,46966,49551,61063,37358,35377,61416,50410,46696,61377,59351,42149,37366,56958,49374,31971,47752,39307,40024,39319,64867,19037,62074,41130,40886,63183,45943,59683,56611,53724,39848,56266,54611,53206,50033,49552,52716,41022,36376,57689,47703,57713,43373,43364,42157,61766,45574,65407,42002,60144,47265,57836,60266,54493,61768,31781,59172,49891,36146,58150,41124,53646,39652,46556,40253,62835,54473,61498,44928,58242,58372,63751,52126,40894,52564,37736,53691,39473,43132,35424,46056,53522,54693,58172,47526,33820,52597,52808,39889,44166,44841,43541,45669,31099,30053,31703,33451,32363,56270,63041,58584,60806,51459,50068,62789,31066,46628,50006,56960,34820,59693,61339,46834,37896,62123,54673,51869,62723,30015,41432,45772,38604,49140,50165,47932,36485,61234,61331,52431,63096,54422,37550,36108,37063,36657,32347,45249,35087,61336,60741,62761,44339,53523,32201,41436,52674,31886,57877,52135,60842,44963,56683,42245,56874,45314,46065,47947,53065,57260,38896,35451,52635,63120,40692,50297,39690,49537,39986,26031,49926,46574,56810,57377,31909,45510,56954,53219,61326,47764,56586,31250,50292,27676,47209,41908,39877,35144,54647,40193,35903,55778,47130,42201,44156,57441,34787,31071,36057,63482,62822,61427,35406,49403,36880,47015,57339,53033,30943,36509,62043,58841,37094,19071,40370,44498,59777,42730,60347,59585,54211,50587,42179,53139,40909,63818,52845,58036,61075,40755,45340,60020,45989,64672,51654,60628,34819,60407,60866,39129,62440,43494,60527,53512,54463,45632,40680,57804,56147,62458,56690,42097,59621,61048,51701,52430,57397,52696,34193,19744,43762,32205,35018,41278,43146,58151,53060,51311,57663,57643,53106,24606,32419,60411,41848,41064,62875,54740,46094,63002,33966,36034,42976,34557,34610,22355,59850,40929,42659,24810,62047,61623,60090,50844,61871,54645,42199,37673,31525,29245,56364,41106,32075,57706,41325,62614,46976,63112,36213,54600,45178,47349,45830,62828,54797,29081,29269,60572,35719,54836,60552,23132,23948,51309,48369,60661,62687,40966,56519,58754,37917,56687,60561,46060,57069,62073,56975,46052,35397,62065,60571,40878,37270,43462,48162,48177,31353,49253,36136,57810,62285,46575,56337,29203,58033,57105,40282,58984,52263,34807,38321,52652,37263,45658,50359,34504,49812,36496,46930,41795,34660,59213,57498,56973,40363,32823,35797,32952,40477,42629,34233,31045,29274,55648,58772,57112,53450,51115,56242,42130,60603,36872,49370,57994,52138,59756,49027,62597,57714,41275,63207,51351,40183,38839,42692,54008,52066,58855,36924,41723,59487,47168,41125,42651,48699,38690,62638,53914,29219,43287,49582,56709,46861,58119,43065,36557,42738,57847,60936,59830,39950,52711,37415,37484,47919,35187,61223,31042,61770,62808,40773,44568,37022,61164,60523,34780,60903,52379,37034,48112,29408,57020,53578,43105,32282,51790,36507,57350,36295,40229,34651,35730,36355,35447,48703,48888,60659,59635,46112,41922,62678,40786,30711,42934,31614,37818,54333,58023,43005,36169,36703,33985,50443,62446,35450,40439,60683,53148,65396,28128,34763,40102,43150,36044,40764,24716,47266,51955,58022,41059,46767,30714,39842,40970,61819,61745,19057,62295,53028,52143,45770,39103,55367,54247,60255,61124,47679,58004,35393,35032,28511,41504,38123,29840,61624,52717,34339,34801,53961,29744,50886,56507,44124,58945,55456,49250,62561,61861,39999,37801,40391,60171,62495,43200,61915,62850,38821,54254,58149,57107,60404,62782,61154,31176,43513,59272,48424,36351,33851,40632,34677,61002,59161,58863,48250,42210,57408,53749,59956,40846,39660,28674,29629,50258,46477,35235,30954,33596,54619,62567,33556,39458,49362,50696,35745,42473,39825,58564,30803,54515,38892,57874,41329,42209,44488,33784,33809,58542,31559,31821,30842,48358,43314,48018,53352,56928,37690,35049,39677,35984,61379,33482,53973,31194,44903,48336,52320,58040,46833,32165,39815,47329,38686,53447,36752,46653,39205,43415,32120,52269,36031,53197,37284,54081,55932,46915,59828,56914,63148,53377,41029,49321,58433,62067,32019,48631,60706,40715,38591,61961,43423,45515,47247,44368,57973,41936,60729,41944,60235,31535,58807,62460,45478,35313,36267,52896,31795,53049,46618,46394,35700,42563,46301,65398,46634,46001,46022,50767,61831,40709,37096,57651,32617,36098,59474,47146,41814,41435,56771,54504,51749,51876,34629,43712,38638,40919,50783,61029,48011,39712,44175,51578,37819,57716,60533,31945,47150,34817,35346,49527,60682,30765,37562,49064,41794,44495,25476,51186,36288,62504,33850,62042,40704,51771,52460,41659,54754,52591,27555,31618,63128,56287,53434,39263,61834,52340,34380,54823,53529,45350,60097,25444,57757,49837,36702,42532,41405,61319,51855,35193,63293,30539,39511,52438,58803,56527,57903,48301,52256,61478,57152,45886,36761,47998,53899,48072,52980,48877,50419,56653,52458,39376,25176,59815,36816,52301,50404,52526,39769,38134,51086,56829,59259,62468,31824,53715,35266,42089,37090,38448,47008,48702,51918,29531,56339,36594,28622,49961,30640,47468,50931,39034,62477,44829,58308,46674,19521,41510,46312,36363,47366,45769,44066,37987,61132,35492,62085,31590,48434,52408,56418,38650,56987,43889,37018,46303,41732,62068,47542,51671,19042,41358,62492,40975,47651,47541,50099,56444,59356,44878,27812,44295,31607,45756,48364,35701,29505,61767,58502,46947,53744,35864,36949,51103,48363,39561,39498,36302,58716,48751,33957,34574,53218,52415,61774,56790,50843,54843,48247,32167,59403,59656,50600,62871,57913,52230,35380,48471,50996,39664,50707,60406,38159,39557,48899,59619,60960,60892,58052,50396,45219,36199,37235,51001,40769,48765,40268,31711,63481,46585,52179,62757,56390,53748,61359,59216,60727,42451,62127,62811,29352,58638,46040,48096,46007,61884,48591,45977,19383,45208,47669,54233,31680,59682,61566,35055,35188,31697,44303,47886,60660,61086,52607,45917,59748,45193,58644,59524,52787,49189,37242,39750,49044,59951,41270,56803,54381,19072,43277,46428,39082,21632,46354,60992,52134,44605,62206,36293,41705,49150,52849,51096,62633,57901,48235,62641,44951,43733,57074,50542,42306,60400,30631,31058,41071,51798,63158,42927,63749,32777,45866,34000,50327,54699,53635,60740,54280,45398,57611,40335,56614,28268,51107,53339,45590,28822,48642,58602,58037,33649,44807,30874,41137,56535,49838,33943,40504,54264,36435,51079,42260,44337,45785,51823,38817,60685,54511,34508,28572,52668,60410,62813,54255,51966,60330,34151,42162,50390,43046,58580,41647,61105,46748,63143,42728,33439,50749,49256,60873,36253,35604,60112,59550,33647,61992,44048,43510,57270,54491,60743,56456,40447,63310,35319,57639,51276,44273,41024,35694,61938,35456,51709,52957,31773,38401,47767,54532,50395,60071,54530,39081,52041,57067,56696,38096,48352,57727,62186,62381,58699,62152,62896,40907,42454,42737,48759,61361,62348,31240,60647,51582,61981,42982,54219,45900,36107,49529,61436,54195,49276,60237,38369,63045,54657,30551,40828,51562,23080,60546,61754,36420,55444,31877,50117,38901,47192,34602,51900,48735,52500,49142,41934,38675,34822,50834,34699,56422,31229,34528,61619,37680,55171,34778,49810,33921,39793,19543,19334,48455,19259,43797,39927,36462,42253,63684,48044,37880,57919,56757,62426,56846,39546,53585,58421,61394,35260,30889,33093,48844,19077,51877,45587,39819,52296,37037,43886,52031,46780,39847,60043,56504,41252,51140,37566,45151,59765,39556,60827,46341,40218,36694,37234,19075,19309,19610,19294,19715,19600,19163,19322,19106,19216,19723,19612,19174,19579,19332,19238,19117,19337,19355,60766,49941,45566,36227,30685,34214,38645,44065,56994,54866,51865,45636,60788,40954,40827,46175,19043,31117,48670,40134,63251,50629,44633,38608,43763,40629,39915,38751,40237,49936,63026,62981,62986,62987,62995,62961,62962,52383,34643,44230,39568,47301,41260,61085,43863,41878,41955,27116,53656,45083,38818,46790,47204,40392,30831,35634,56254,47157,37313,41989,50371,35212,57688,61764,46551,39803,31018,60341,53246,56967,38554,57620,40533,49494,49883,40481,38779,39653,48509,42725,37147,45132,35452,29801,36211,44961,40052,62877,54277,51241,47845,56794,38820,56938,48107,59962,50808,65093,42357,37374,55410,39270,40316,51735,33695,47937,60976,31523,57094,57845,38876,50821,61460,50816,60958,45123,39378,31171,34696,58137,49894,58309,59767,56593,53166,50403,58229,53011,47075,34911,62906,53688,38999,42706,29688,56950,62454,60855,36193,52708,50801,63044,48022,42729,61444,52574,53625,46339,35490,60651,31470,57393,59017,45075,43998,60022,52766,34067,49873,61035,57777,44051,30014,60461,34494,43286,28523,44922,37089,53045,42740,32239,56280,61744,52190,39182,52247,49764,31343,44539,34173,48436,53235,62084,59980,29363,54004,40014,35810,56265,49440,41030,56772,31555,50192,60129,56632,51175,28361,42909,41391,62153,61532,63087,49010,61010,45192,61301,63042,36461,62024,56791,52687,54022,54183,54029,54026,42594,54020,43545,45810,56491,53465,38054,52496,40952,62548,56316,57419,38555,48937,41646,48199,34895,45185,49447,46613,37911,57664,49644,43434,52166,32410,37424,60589,35355,63166,31382,40026,39201,40352,58707,47677,52988,40656,31410,56564,58076,38109,56643,33441,50897,54159,41147,35030,54010,29395,46889,31754,34741,57965,47274,51772,59894,34413,59241,54148,39446,50261,45347,38377,40685,48109,37267,43463,47517,35110,38375,44646,31041,39910,25162,36020,50784,39019,49187,56247,52890,49132,35084,49106,63627,51726,43670,54625,47988,47994,41724,62698,61639,37582,61400,49371,57184,35280,31248,49916,34086,19562,43042,58559,50790,56980,41309,31289,39391,47233,29867,50912,51797,44282,54230,57169,56508,51300,59907,46603,57259,45963,45195,49980,30683,36264,39814,31372,60244,58649,59551,58284,44194,40736,62951,48080,62933,62505,52844,58375,57766,52539,52461,57562,63472,59560,47955,46595,56814,53233,19464,47410,46902,46598,49971,47313,46901,42745,35973,63270,47203,37316,19348,19663,19369,19185,19024,35457,38033,40128,31534,37586,32051,38946,57920,62743,43416,45481,34515,49739,19746,19444,19410,32090,19364,19604,19176,19110,38484,35396,59167,43032,58130,19577,19148,19021,63021,51780,35401,59529,50289,60267,53746,57946,48862,54659,50007,56727,46737,42231,59819,45520,51847,49080,45979,38734,36164,48928,19246,41998,41954,47963,34946,48181,48700,46092,61968,39808,32197,47852,57725,44304,36695,47630,58849,25251,45961,35020,59776,39074,61371,51959,39739,46396,42156,47304,53750,61890,39121,62739,60662,60924,54272,35198,34803,31119,56166,34317,62480,36536,62238,38912,55130,34456,28538,44200,49226,53242,62361,52222,56658,60142,50962,36369,46520,56318,53213,39165,57911,59935,46168,48543,39696,46763,39163,41738,62178,48325,46531,52221,45944,40213,56417,60077,57705,47785,41572,32138,40714,51860,44274,19501,43776,39494,19462,43285,59475,38100,30484,19016,42194,53926,58821,51822,61001,55544,31621,60963,45652,47683,57365,59750,51047,57980,57303,37535,30894,35580,30875,33146,62536,62579,61064,57470,61956,49293,44881,59478,57963,28022,53163,55490,57634,43344,35493,31080,54389,40835,35342,42265,62636,58545,43496,38683,50532,43981,41289,19385,47972,30919,27954,58550,52551,38538,41768,44441,57338,40993,63470,44805,37179,42440,27988,19504,38320,36155,40944,27873,51239,53695,46672,61911,47496,54761,52192,39759,54106,52544,46669,45031,47288,57696,59579,38454,58006,56609,60199,48520,62078,62129,37392,45274,55261,61145,63758,45035,39135,50968,52883,54691,54338,47540,53649,35327,47509,40821,44238,63027,44324,50057,36042,53888,60239,59279,60035,61323,58574,58866,54354,38232,48006,52020,29373,39462,49610,35854,57751,37791,44346,48071,26871,40384,57971,47871,41866,53532,47782,35884,19541,53547,47598,39167,56506,56260,60132,56284,57025,62340,47337,42198,52486,41495,57742,46505,59728,62627,35104,61240,53154,55494,57543,46726,44361,42723,40979,50818,47586,47095,50859,49694,60691,35240,61547,20647,57172,34398,59166,46803,35735,61908,41105,36863,31015,38431,37794,42614,61431,46587,28099,35640,47508,62759,53435,48730,27953,47861,49368,43001,53473,34757,42032,19419,50895,61869,56389,39816,60340,36690,30282,49113,46296,52433,35136,43252,49105,40346,19318,43803,46338,35951,49381,46400,59138,41833,35152,62842,56544,56256,59302,62202,57584,33667,60573,41337,50409,40081,34925,37118,48160,36515,61017,44596,50391,43861,41511,37699,30123,44810,38593,39648,39820,31671,53546,58588,48236,57661,61742,35287,27517,49363,31916,37378,61375,56222,29630,19168,59856,53600,35993,39395,53753,52604,30983,61203,62221,62690,59875,61457,52707,47758,34435,44671,41652,51290,37200,38229,49520,58572,43029,63049,50563,31797,40659,32188,43221,62777,44654,19476,48342,42578,60688,39061,57100,33662,52146,60916,44474,45136,44630,39059,49510,56225,42378,43244,36804,45821,54130,59725,63309,31805,48545,35838,62240,54000,53680,44083,41437,55265,59891,40989,45635,57930,41901,40547,61681,31409,36628,47336,60454,59827,63124,63065,42514,60777,50878,39316,34178,45968,50737,63250,36885,33543,58877,49278,58397,51390,46515,56398,42724,63899,32535,61543,61865,60054,39632,57646,56446,51696,57900,59578,62349,44074,19422,45296,41556,38120,47704,41836,62410,64387,63303,42781,49087,43429,45992,37721,36788,54373,56724,37760,52649,61806,56923,62168,41290,54293,58835,35992,45262,45914,39550,52034,37793,45508,49252,56447,41272,39301,38200,57883,61215,40296,58424,26171,43372,37254,50768,43383,46116,58306,56802,27949,31028,61850,59253,38617,37621,53330,40168,32954,37015,49141,34509,57072,45155,59873,46845,49085,43074,57181,51126,47461,54596,50200,48933,41534,33699,44123,42114,31298,58046,62938,40060,62985,53289,43880,58351,37650,31025,41966,53395,46912,60157,57156,48927,55881,56392,59115,39085,30528,47905,62631,38599,60068,46984,43162,37804,63231,42766,49263,38557,57819,51960,49417,35316,33653,57559,47210,49526,48382,57347,55579,28029,61761,38958,61340,32258,45584,48661,29548,43819,47836,30133,49100,27170,59127,40513,57505,43262,39077,46277,61673,56278,37278,63422,47551,28713,58617,44884,39078,59542,62920,62081,35314,44566,35491,50969,53549,42061,61853,39433,61730,45741,62234,55533,50041,57401,29349,39058,54548,48996,53095,44287,40434,48305,58234,40759,51344,28237,52819,34795,29151,28464,38827,42508,29093,27933,28680,58510,52967,57806,48492,35038,46534,36959,47929,38619,46504,62711,52629,63005,51774,41776,54662,47030,34837,34832,33003,45095,35469,58739,53893,57947,46387,38528,32050,58458,57499,56630,53525,61315,29375,50675,31172,19094,54505,59437,62228,23372,59169,31183,41808,33552,32147,61158,45818,43354,39147,62563,27910,48193,61608,49052,56812,61712,47680,38624,58380,61239,61055,49979,48845,32125,30915,62941,37437,33471,48003,40465,48007,41674,51495,54158,51859,63739,39687,46693,34955,46594,45018,31938,58182,35613,48481,50916,56157,61289,49985,32724,36141,46020,40781,61997,52832,40483,44843,43410,43422,35157,42510,31252,47354,61707,53877,35607,57654,44381,56412,34451,41234,60874,63281,31794,62541,43698,53984,46658,47405,56215,50060,30942,56436,31407,33648,51253,43748,50493,43424,41785,61249,62113,58567,40641,28941,61046,44914,35718,29291,38499,54231,57678,42058,57744,50887,38389,48454,53657,57229,53073,61260,46147,56922,31221,60013,62459,31285,51746,53462,58385,53133,45278,60418,61213,60238,42298,36282,28006,47799,41412,31996,62164,36308,54604,60198,59798,33027,50925,49322,49243,62763,50863,56972,51484,47831,28658,39651,28023,31658,39493,50777,58359,34266,40554,38102,45544,21417,39623,62758,34653,43843,36494,38507,60906,39939,62990,32172,53445,19350,56269,37259,60452,30870,41348,60360,58976,57153,35578,63003,56430,61314,46123,57320,41686,47137,32740,31646,55045,28517,47701,50991,59638,30606,50070,56116,57848,43379,57343,35247,50326,53478,43478,35821,46265,34019,41764,31254,43442,34840,33569,42442,41146,36946,62023,50933,47176,38419,32122,52352,45570,61883,52381,37345,51093,38548,48815,53351,39352,52624,49841,58693,52406,59014,62116,34717,61116,36697,43518,39603,49030,45323,44872,28726,49577,47113,27939,20435,61207,52145,53929,49093,50905,49759,45376,62596,36734,50998,32257,34879,47151,30945,38305,48317,37465,31745,43760,41237,39635,51971,62525,58697,45244,44482,37772,42188,38005,35497,45320,43181,43840,30980,31095,35253,57575,44102,42275,47899,36012,54110,34134,48122,37197,28545,38303,46246,53252,33698,32509,45629,62246,53025,30881,61087,53630,60547,51474,38489,46667,60610,53446,31169,36456,54870,41049,62098,43257,42240,58591,63756,41781,46774,57702,57366,50072,36100,49725,46017,57327,39148,47225,40852,61072,44440,36926,63091,43879,45034,40732,43484,38671,53451,60859,41317,38609,34710,46722,37225,49757,42350,48128,60070,48339,46044,48398,38186,35828,58412,40834,36488,50373,34667,46405,35089,47783,51267,41933,44110,38156,40234,49973,62724,63305,40890,51936,34679,62922,63278,35074,36932,51208,35839,46814,53176,62671,38930,36266,49942,62278,40393,30194,45834,31881,60361,31375,61626,59977,46848,53298,62942,41126,35061,47547,31454,49184,44452,60545,61454,44131,57428,36040,61321,31318,63061,31987,31681,39626,58623,52195,61381,60242,60878,45409,36835,47880,57010,45033,35046,46115,36226,42935,19076,31624,59133,39354,38938,19658,53322,62717,52552,38373,61753,61403,53628,41899,58941,20433,47970,39526,53951,43095,51313,43210,58555,51348,44518,50285,46149,58554,45811,46386,57248,40019,49983,35196,48903,34858,55751,36053,58010,51236,60462,51213,36808,52589,49428,40277,49279,41739,55015,57063,34953,42145,57148,34603,48935,63067,48337,45282,39497,50848,51165,58303,62765,60831,63090,37291,34099,56362,40287,40863,35382,41006,40505,40486,57658,47800,58871,37353,51215,48334,61557,52798,47908,50671,58925,56786,35656,35000,47251,37883,46047,57997,58368,58434,46048,54288,19298,56752,56774,48697,56365,56833,56799,56755,42646,57425,57427,65100,56333,56335,56304,56822,56241,62383,47685,33974,33997,33524,65018,45617,33239,52791,30603,32470,45993,45119,31175,52517,59561,50090,40241,52469,47043,35819,49399,60100,58399,47104,57497,34399,46779,56336,59412,56251,57839,36599,41886,43156,62128,51091,41347,57933,46719,56776,33102,60448,47462,49164,47200,49501,34663,56813,56355,56685,56202,32761,31778,31954,45814,53119,47001,35944,58128,41660,60820,48859,36310,40228,63471,55434,56768,56746,39109,56625,44330,40670,48932,30396,56349,57319,57080,46560,51962,63606,49217,59104,47394,60964,59700,45188,55313,48772,41320,42216,47401,45260,43205,45575,43044,59054,62604,46023,32244,54486,42371,31513,59862,56851,48794,52750,40540,61335,35900,47459,51887,54768,57346,60126,49761,32434,65408,56209,65138,42700,31239,38776,47884,56301,29606,42753,51316,53765,33932,60664,62306,59857,59738,60204,56151,49934,39581,29529,43297,38996,48529,58494,62622,37520,48259,38698,35599,53031,50546,50549,62185,31308,34818,48198,29589,41248,43331,23183,51849,53766,60614,49251,52806,48992,56642,40456,53995,62783,62025,54638,62200,42099,62568,62009,54210,49627,41110,63024,51725,59934,55586,43009,50065,57418,37171,34967,31834,30052,59471,42147,38819,48662,49608,31501,51396,29422,34273,41296,32528,62376,32560,51973,52384,53987,49660,42062,62136,51675,35445,52804,46870,40898,34949,39654,36245,41311,54461,45537,64497,38230,60258,62859,55413,35064,58599,41353,60928,58376,62762,46214,26963,42755,49349,41789,52961,50173,61693,42430,42695,49190,39618,41175,34986,52686,59848,43438,52619,43974,61476,49925,39867,54750,44033,38464,42743,42229,50918,45232,34486,35592,56824,57313,59179,40546,52174,60771,61827,51924,34962,38685,50568,56279,39410,58801,41471,48326,30381,19576,29854,37370,42512,45085,33094,45529,20740,50856,38761,36974,58942,48105,46855,58714,56152,58799,52976,41411,19282,37166,60195,59085,46319,52001,63203,34165,46732,29507,37860,59076,57036,44894,59039,56290,46742,62524,62669,60644,46716,19491,60405,49831,39083,52377,45043,55926,46542,37102,37921,60441,28292,60641,56380,57233,29448,52030,33158,47925,56974,44954,56261,48028,30483,33886,41688,30278,52683,31456,34294,48854,55806,45602,63480,59759,58358,30818,52346,54197,33868,47600,61000,35969,36904,35740,63312,60629,30641,45223,42470,45201,61182,48986,54612,52325,45789,57878,60096,49463,56949,62940,39616,35275,56720,57186,58922,58927,43362,57200,45150,59923,59673,26509,30338,30486,38793,29066,56250,62982,41941,33643,52317,50300,54758,37521,40665,38315,41298,43738,40357,62483,42010,38655,37859,55460,53057,38444,19416,48955,60138,51170,39680,60940,54258,61756,35107,32302,31161,46783,47129,34907,63586,46948,19566,63113,31384,50635,61778,49575,59262,57525,58122,19457,63467,60052,63201,43138,57931,58938,34549,56594,57602,35741,57551,43808,47311,46366,52465,53037,52540,47495,54468,21585,30708,45248,59390,30505,43839,31528,46279,31086,43938,49896,49917,63114,28472,34936,58626,51076,60972,29393,52453,32091,34275,49858,45981,45362,42223,57753,35933,35915,43825,36085,43060,61412,31489,58621,36607,57793,52399,44863,47887,47481,44140,62786,34958,35019,28774,31047,35961,28609,40096,31572,57929,32052,53516,60630,47803,64508,31443,41070,48521,47126,52056,52080,38809,45696,62375,56257,41828,59976,52165,46460,45421,57732,33877,30636,19515,60203,33736,57907,65030,64856,37288,48906,32110,54674,59766,40468,45802,48152,54560,43885,62570,54614,30644,62052,43125,48883,61106,34374,38915,62334,38644,46529,48307,40938,51802,51232,60997,47097,58959,57882,31769,62441,53554,63213,63191,47072,61746,62899,58180,41306,37483,62339,50064,49884,22801,36777,36882,37281,40861,63122,50381,57771,40684,58516,32361,47504,33400,33368,62578,48791,38952,50472,54064,59035,59111,48966,57309,45167,45585,43213,44183,60686,56877,33309,41141,36112,43741,36225,37042,31282,61429,44619,49738,37021,40313,48790,39104,61094,59800,33413,28783,47134,36127,35467,51628,39555,35564,36726,52926,30710,58674,38972,62366,36517,61262,61736,29170,41273,62884,59255,62666,44002,50702,43155,19584,28163,35851,44803,61230,52152,48469,63010,58055,34733,53521,60365,58353,43959,48805,59959,32150,58195,59010,59699,33821,30841,50951,56982,48505,39997,59219,40217,31423,37761,62467,54592,38585,60978,56474,60211,59055,40436,42698,55435,31739,21771,43679,48705,50474,59921,29087,49965,53983,31507,37006,62267,21725,31530,57996,43688,58761,45431,37665,36317,59897,63832,62253,35766,40526,41295,52488,50502,45389,40644,62415,30293,40373,35112,57894,41356,57641,57421,49372,61084,38309,33382,37241,51391,52361,36157,44933,39386,41669,58669,48244,58225,32921,40968,50762,53076,35334,29379,40600,58181,58741,53162,40124,32663,56196,62989,38679,42599,49847,51194,62957,49897,57798,49907,58829,54024,57383,57728,28365,61493,46920,49909,61168,61284,53311,48331,58955,38754,30887,48897,38425,54637,35218,32245,56868,44688,37544,59020,62243,52664,60562,61342,42192,31595,60218,43322,35865,60879,59618,49544,47305,61925,49303,46252,57868,42163,51042,34896,41710,35435,33951,28519,42294,54102,61206,54326,42917,54003,49247,31340,39091,29410,37759,32590,61190,35947,40726,41953,31566,61421,42107,61350,30601,38453,41152,35498,33260,41328,60271,61211,53277,57789,60689,36700,59987,48489,57433,59883,52370,58769,58789,59280,58341,60139,59710,62978,38630,45146,36041,62149,45217,61977,58710,46868,41824,44814,33689,41546,19289,47297,34908,39538,31752,58688,58679,43495,45969,44130,39119,47132,40519,43418,34748,62812,42203,54678,42048,31448,56258,38137,54661,33754,57729,51031,44024,58948,58832,57360,19492,46082,28428,54861,31181,45902,61458,62451,47589,42295,61329,52015,33089,57762,33237,46533,58685,45012,56976,40591,41282,36982,60048,52306,57630,46093,40568,44212,33702,45494,45461,57603,60294,51281,50335,48138,40381,53711,58039,27747,61692,58227,52999,43802,56394,48248,39909,41958,54400,31529,34133,60553,61677,59895,58391,57722,61862,54752,40521,35407,50845,34438,36175,52751,56934,41080,47950,38067,62015,33962,41201,46639,41102,31829,52185,54191,47585,34672,45986,40822,35283,58484,59650,60302,40728,58067,42748,45445,28762,59397,29384,53632,61448,62674,31322,63055,58213,41780,41094,33704,54599,41830,38074,48866,62135,60484,49314,57071,53735,19247,43164,35185,47770,31731,56979,49966,58343,37029,61696,46600,59837,34961,29374,53947,32054,35353,50920,63001,47440,51919,49997,52032,61155,31478,45438,60742,60191,62618,49086,32953,60073,59822,59303,50042,35939,60367,57455,45651,57508,46309,46148,59867,59821,56988,57413,52625,51243,61285,38836,42912,59231,50364,58633,47507,38284,45408,52105,56756,62909,40811,47791,48134,43986,43767,34665,62087,42543,53021,57876,63018,56367,51807,49846,43870,51846,59594,39228,46378,32322,50478,61254,47505,30810,41389,33361,60543,33418,42464,60534,58628,57415,31616,55655,61536,61221,52643,36298,62311,56518,49819,48190,56403,61507,56784,34472,43993,47668,39069,49533,31983,51335,50612,48211,46967,57429,41807,61376,62248,62866,62878,48549,31836,63206,46535,59784,48418,54412,44222,58469,53774,59267,38880,59511,36833,40813,62838,58330,34685,59812,62188,47599,63161,38184,38163,50535,19097,46850,45341,57161,36066,30925,33392,48233,45103,60444,60015,39230,57937,48223,44525,45864,56670,43400,57998,47554,52815,61411,35917,32757,43500,31556,62858,44256,59758,61846,48313,62518,30993,51034,44950,43272,54291,54207,35776,35165,53797,42082,50773,52885,54351,53341,56382,43309,42238,40869,57494,60846,43072,63152,36439,51620,56291,39499,50194,32227,61191,56220,45645,31094,53620,52420,48387,64024,59455,31615,47456,31481,34172,61703,43995,51693,52570,41924,50831,60272,32012,50936,60825,44697,48941,19477,40142,32001,57306,49612,47635,63134,42019,59305,52714,31964,40331,47273,46635,49653,44974,33565,60021,62059,43417,47735,50077,55632,45558,53564,41253,47672,34544,45611,61307,58613,45238,36452,49952,54457,60270,56248,52439,49356,60283,57420,48706,61672,34108,35202,54561,60143,42104,31694,34284,61068,39774,50405,61006,37330,50304,47309,58160,19258,35844,53303,52300,33823,58524,58765,47642,34849,38774,48733,61143,52422,47582,42515,43407,34969,41388,55459,63014,58507,19286,31663,30804,37751,48912,58519,52755,57507,57886,56773,47790,47519,47916,52620,62947,54235,31206,57684,56409,45015,45379,61892,59504,58891,58670,36898,42171,60039,33885,58189,33467,56216,40259,34190,35011,60862,38361,60882,30958,54817,57537,52177,56926,42774,54582,38676,49054,54788,43258,53165,49568,33452,62036,63221,62179,52783,58593,45831,60600,41338,56743,33729,51488,44779,49095,53664,52532,38755,35158,50397,40004,46589,39580,51818,46572,64358,35666,62239,37565,54482,39448,52150,34079,60332,61435,35299,60817,35549,50735,45154,51668,51784,53089,54684,44667,57926,57656,63294,54668,54664,57232,57626,42200,51597,44026,36869,41689,60728,49443,39649,53421,50965,48622,56562,50181,54186,63316,42263,40035,30650,63261,60393,57237,49206,46846,61690,58347,42450,57273,56210,62732,49628,28496,54243,46122,31833,52712,61065,56358,60260,59194,49015,39548,37569,47926,50557,46114,49402,45564,48800,40658,51198,39334,45173,30899,61092,53024,40693,31007,45752,48734,49791,62953,62608,51946,59263,29551,49661,62662,40637,51896,29896,38783,41045,36756,48809,62211,60872,47694,32655,31732,44649,19100,49453,45907,60617,56608,59468,57966,34652,53115,19285,62351,37619,32230,61110,53638,31192,62380,46372,56682,40091,45775,62021,60839,53479,60704,45735,61845,57627,38970,31532,62705,32059,49709,43934,35048,44112,59817,62244,49770,45261,52587,48908,59235,32681,52464,41281,48098,63266,59189,30281,39948,41440,48207,61573,36254,62035,56396,38625,48452,47240,41101,60658,50433,44322,56395,47299,49214,46827,49211,48756,49754,49903,47912,46943,49781,45317,40339,56401,61759,61135,59741,55056,57129,41656,50286,58694,61483,42219,62648,47773,47102,43474,36812,49506,59341,61346,31150,54682,56405,42636,61973,54316,43404,31748,60671,35024,49545,46523,47218,43041,31426,37639,35845,42621,30688,37190,35027,49995,56689,41467,62784,64118,34690,43151,41194,42713,36113,37439,38249,52536,49012,35863,41473,46673,43742,60736,50881,30013,57748,37657,61025,58566,51633,63009,59116,29820,50415,31444,51402,37532,62645,57147,32734,47608,62945,38219,28053,40798,45663,50708,35106,47553,34130,60933,51377,36786,57058,60697,46345,56910,42757,40543,62191,48101,50023,34041,44958,47943,36096,60185,54769,63837,45205,48183,48663,46480,61083,41975,57828,52283,49602,57217,60146,34775,56472,61404,29295,35888,62438,41694,36876,56860,47760,62097,49878,58899,44326,34060,50983,52939,36538,62201,58543,45485,52236,46530,39273,45546,36262,50915,60975,49797,59053,31771,57314,48535,37802,62099,45388,56867,48551,31863,60333,58445,29617,47220,50626,50407,34017,57033,56187,53922,31608,48206,60428,51264,56667,57070,61773,34545,50548,45719,61114,58620,58645,49946,62952,38950,58057,61843,58058,61844,56686,35561,57552,56740,60094,49397,60638,51219,61091,25319,59788,53928,60537,33573,46650,52510,34245,48553,51778,35228,57285,47429,40040,54526,43320,57539,59040,46036,39080,54570,51024,40080,33453,62390,31760,57822,30089,47383,38678,43033,50573,34531,61688,56650,62733,62887,48497,59691,49871,56748,59291,57582,48620,50880,36809,51013,59810,35748,63473,51622,42623,59664,53487,55259,52701,46390,58949,56647,52558,54123,41792,51063,62832,45463,45732,64874,43058,56977,47271,28654,38978,58629,58993,40767,46880,40042,60929,51111,43962,28833,46925,53916,49535,49658,32501,53097,53586,34251,51159,44811,45183,48575,37025,53942,54639,44823,40262,60464,61463,57593,60128,28606,28989,51027,53757,59884,40842,50547,56940,46651,52392,62973,37492,56440,34191,36764,39100,49675,35029,53572,59844,44300,39748,31762,57909,49425,28505,49561,48017,38790,57312,38796,53636,62697,50104,61189,28615,40208,30323,42381,30931,63249,39198,40748,35727,28518,53530,51363,30730,47571,53528,55613,32875,46099,37626,41670,34383,32068,53464,38908,32366,30537,62371,60700,31952,33060,47391,36391,53767,50964,46582,31802,29745,57694,63276,59559,54529,32066,62245,58173,36221,62104,51792,62060,62785,46566,32306,30946,52616,41067,53500,59986,62118,42754,46687,57527,37693,56404,49415,57180,61397,47453,45639,51380,52576,43595,45678,46043,54297,61937,29350,38089,32641,57352,57625,45622,63248,56889,18581,40669,49712,61904,46988,41726,58091,34952,60800,57394,41788,59409,54446,56744,36836,63228,44208,40425,32548,52572,57151,48696,41766,61792,46057,56204,49659,57838,59886,28031,43288,58786,35772,54801,59310,19184,51304,37019,51980,47012,24932,36527,33955,51237,51698,35553,50022,49404,46100,44789,37453,40590,39463,36780,60034,47570,40496,45008,47634,58978,49762,59134,41921,49646,27470,57283,62552,38301,40508,55118,44588,59942,57786,56533,60500,46070,29088,50804,57854,34970,40971,46247,43684,47612,35344,59274,52267,34157,54679,57160,62432,51785,35531,40219,49828,59961,31249,38736,37438,40520,46166,62106,34622,47910,45200,56907,60042,61906,50822,38657,58751,36105,60322,40255,41425,54044,35203,54166,57621,52060,59224,38106,39913,43857,33804,60747,43242,31725,31385,60287,60532,49887,34688,35425,62715,53332,36823,35040,44502,58962,57733,45514,45111,47724,57051,59582,44382,63106,58475,54244,53725,42064,60161,42921,62268,38634,44866,46280,58108,41678,36847,58917,61024,62481,58491,37817,57128,41310,40567,43089,42182,39553,43775,41763,34654,41913,49167,54118,41775,46437,52562,31806,31801,30731,46113,19265,30614,57231,53933,58337,46584,58112,56201,57679,51932,31575,51019,49532,50209,47241,54489,52280,48237,32846,61490,41657,56384,28602,51367,36686,37797,35596,56830,38668,58775,63764,39517,43038,31446,37885,58474,44842,60945,27808,37664,40888,59734,42647,56146,32045,55213,44992,36666,39930,42098,53915,51205,60338,59427,59425,60378,55976,50766,48213,63025,42063,37324,19736,48731,39656,52632,31312,51362,53380,35472,43834,35670,37443,34243,35453,35465,32544,50982,40754,61062,62815,51691,58156,40694,45599,52636,45822,41187,48278,37747,47094,47306,42686,40611,29937,30011,40489,48725,38565,53258,45159,36663,36574,42503,37930,31868,46588,63744,55685,30632,52295,49556,41284,53019,32453,46609,57976,35459,60477,60194,48431,42375,38620,39066,59546,19727,45281,42353,42616,51190,48318,54676,62928,39142,44716,61506,47422,50155,43667,63317,52666,56460,37340,41051,43203,34868,27964,54498,40752,60155,34207,55707,33692,28560,37196,57211,36960,59018,40461,54713,53884,54617,56694,48724,41720,55390,33781,49065,60566,38858,56645,28265,41525,61057,59866,61011,58752,55656,46738,53501,39802,43066,41709,48548,40815,49002,53575,58120,58921,47035,48667,47772,60085,62236,35230,44242,42457,57114,44323,42301,61932,44959,48201,37033,43187,46675,62272,40400,44022,53178,53107,39519,50136,43361,62235,48654,35221,52013,47221,37844,39956,39811,35371,52337,62360,33589,42239,40151,50993,43719,39441,57927,44973,41172,38277,59572,54855,40850,47165,50250,53113,53958,40730,56818,46691,54513,50894,46752,57106,47242,50632,23931,43965,58770,54226,34815,60621,47316,60710,52648,60180,49094,40334,36478,34767,62343,62034,62019,60350,43700,47367,50615,31779,51840,34484,47447,52850,50885,49955,29980,46471,27866,42080,31069,61958,18999,40172,43282,41664,52867,47965,48332,35563,46884,50353,33728,62798,59239,39935,47470,54318,40050,54650,61791,43217,63314,34854,46707,40077,53949,31789,59065,34753,33058,33389,33046,51880,53316,57011,30924,37688,49020,29824,58005,51885,57939,32858,53468,42193,41372,32608,56701,36036,62294,51330,41294,56484,56235,31858,41195,38460,60427,53404,57028,52156,52958,34995,53412,54967,44457,31447,64580,44924,50703,58210,56864,47588,31505,53470,39366,50422,42989,49902,30399,42602,49103,28666,29971,61711,57207,41218,35449,61687,62523,45966,53046,56522,40901,42995,40633,41771,44788,47384,43062,47811,44004,53432,62876,59947,43171,29724,36202,41231,49697,43174,46355,40537,46645,46078,40226,31969,40222,31865,36093,39033,59965,56573,62224,35560,40227,55418,56825,57607,19583,39013,37700,48464,41313,41679,35274,50255,38498,48026,53881,45406,61378,53484,55075,49444,50874,54818,36018,41540,43281,46508,32231,38750,38292,52565,51217,37596,51949,47794,35421,37307,54181,44335,34655,53615,51438,34712,37908,30822,59125,63223,41527,60234,48745,41464,57554,40682,43083,58622,47004,56136,60569,53356,44014,61558,42078,61989,56665,37919,42221,50698,44515,54290,62159,33107,38631,37346,44690,34956,34219,36555,57580,52248,49144,33231,44413,35568,53061,33835,31665,45452,35216,36662,35294,34734,49385,45920,31726,38493,57166,58109,35111,56565,48185,58755,52039,64376,41280,48056,55190,53570,30312,54495,57089,34873,61053,62338,55449,53756,32813,45055,37601,41307,46568,34646,40743,45738,61839,36438,36582,51062,53810,57745,36038,47709,47860,40453,51214,43326,31602,30411,57115,39075,41387,49287,44055,50003,42665,19690,50803,47118,46453,38605,53557,52992,48371,41396,39728,63245,47763,28863,60075,44437,44442,39512,49382,31371,34228,41168,47584,64588,54932,50733,50700,58439,45203,56839,53936,46308,60780,56439,33676,51901,54581,44682,63286,52194,47780,29843,52302,54655,53402,50141,52524,37622,33044,40735,28095,46525,65165,42380,45548,57850,30938,56350,36839,53140,47896,50280,59610,61537,62956,49490,49357,57974,38215,36888,43243,51678,45108,41191,36513,54265,48945,38584,59045,60970,47161,57555,29016,58187,64853,56276,39461,62817,62180,43872,40010,39753,56293,52721,61675,63117,40609,61962,63277,46091,61252,31704,60486,53712,41403,38408,51238,48595,19587,34577,52881,40011,41803,42675,54387,39875,56435,62746,58934,38272,47609,63754,33721,59484,44603,56428,58041,48687,61050,56659,56890,61209,45028,40281,63111,53474,61446,31376,45519,57640,39622,58546,42557,39207,41806,60857,61250,44962,44258,56679,23919,38563,52010,50167,40660,54847,48780,38925,62651,48732,37857,35751,61474,51513,38812,57092,47699,58798,42093,63170,59593,61697,35615,52124,44545,19140,35129,56312,26982,58317,52413,58194,27502,35910,36545,57895,39213,59156,19466,62537,60432,61758,54644,62675,41072,37628,49964,58228,36463,41404,31400,60362,59890,47308,29739,59716,43294,31664,36704,51862,53703,47898,39979,52511,47591,19710,19264,39164,33091,44815,40722,37333,40099,36707,48764,48598,43148,60003,47039,40527,44405,44038,37406,35802,46699,43093,51732,45536,45778,47382,29758,30447,30243,58077,61740,56649,28679,42522,42141,34512,53448,37074,62902,39358,49289,38673,54150,47275,58825,53544,33411,44163,43976,60632,31514,41114,32642,29345,37379,44913,62760,59061,34754,62111,46863,36637,52053,51122,48819,56399,57647,33359,63185,29834,35126,44668,45381,45724,36443,62319,62313,34631,35534,30793,46333,40624,48940,42625,31258,28410,42443,56195,53505,56385,54216,45918,53331,38206,55516,37173,49563,60229,33560,51551,39026,41158,46982,35075,47156,34797,33753,39943,28228,39417,41446,54415,49427,30582,28540,43579,58872,42232,39762,27399,63252,35012,58600,39771,54521,42888,43836,28225,53919,46881,61044,30715,43972,42576,37733,38437,35378,33960,52423,59607,53782,36167,43831,41798,38993,30600,42673,51212,36307,50926,46583,52035,44575,47973,56693,40203,43752,39455,51199,46051,48817,45648,52181,40705,39107,35348,53582,53312,47250,36643,31857,34689,32939,56759,53314,43921,35594,56056,47801,37512,57835,46569,49394,50786,35329,62540,42674,38290,48747,41035,47888,36386,57381,19084,43597,58985,51306,49450,54403,35270,30768,37213,61433,42365,60225,36971,50392,45625,41841,44837,34639,46282,48010,45229,42110,38888,60453,58771,43849,35636,36428,37271,29246,44476,43851,35811,36030,46291,39678,57811,32223,39936,36296,47806,28419,46273,44153,61019,56661,41207,46682,61591,36981,36289,40598,40779,25165,31295,38170,19456,41269,30544,58495,47959,54814,31032,52462,37551,39202,37697,61131,54203,51490,49513,37387,36961,56695,47900,60079,44466,29371,49835,58071,32698,30161,50744,29372,54141,45728,31543,45407,42709,47018,41879,30789,52934,42254,37308,43048,30418,38339,45076,59209,50524,56699,57165,31888,28738,54472,41116,51997,52873,28360,62049,31927,54770,52909,54126,61995,49066,38059,28476,39525,51791,28358,52345,40804,58051,33253,43419,49758,40015,41099,57754,44896,55471,35757,35499,55041,36062,58072,28786,52435,45694,40780,41299,57590,30322,40302,58910,59139,52784,35529,42720,35818,37184,39524,57034,52081,45582,36091,50734,52610,59814,59428,63741,49849,41257,54094,57042,32848,50842,62324,42305,41477,57958,19079,53299,60887,34640,36941,35771,49990,35691,43966,37020,35362,32463,31415,56884,62923,43165,35628,61706,33732,63410,48658,34077,62930,55136,52776,39187,22492,62853,60087,58560,40956,60390,19092,37319,36857,51371,33591,32636,29378,60019,27803,51577,47457,59684,56315,52414,30003,46321,34331,35428,19209,29344,60245,32148,50929,57289,45589,35286,29826,43704,50387,31641,41928,59863,39169,44427,53245,52360,52744,47930,41198,46009,53513,36575,51221,48146,40712,51179,46155,48465,35293,31046,58270,50569,50959,30736,49165,47566,31374,51255,40167,59203,62345,45392,35174,63193,49198,62624,36763,52228,37113,55493,57809,39166,42120,61437,45492,52385,35345,49629,48234,62003,33025,46789,46315,38674,62665,32759,36978,62976,46357,48949,33991,52970,49711,60130,49416,32202,39575,61049,38987,34589,37010,29584,37049,33668,29502,59755,62709,35462,19495,59643,42195,31179,61924,61163,47385,36892,31108,33812,53161,61176,36714,38933,58089,46086,62632,41728,37798,33856,53083,57375,35191,19120,63748,31871,19028,37207,35975,58427,60746,40569,35473,37684,34489,62628,58890,40063,61959,60968,45942,58209,51697,60764,63478,34928,62083,54613,63649,60904,63829,62210,60403,40868,53604,58131,51537,51912,59570,49541,37419,33680,57550,46360,51679,50643,31906,41254,45181,45290,59762,56648,32794,29333,40667,19625,35070,39214,60423,49157,36312,41019,59797,59015,48988,36738,58939,62935,60909,37125,61941,40892,43784,56421,53518,29323,49799,47375,43035,53673,40737,41810,52319,45363,30840,47446,38580,35072,35446,30878,62862,42205,61988,35130,58673,53486,50944,40673,54151,62900,36893,33961,56631,48853,56407,58413,51464,48253,35779,34825,25625,57496,56615,38477,49820,39659,32128,38850,61996,57201,63176,46607,44859,44869,53627,49353,60110,29977,35698,47873,36104,40661,35241,48451,43817,35579,48401,38302,30620,32629,61552,47379,53010,25148,58928,40610,35511,42746,57528,61957,37134,32069,32767,59913,47389,56657,46266,30555,53979,35882,58614,51794,40297,61383,56714,53227,33920,35479,58625,31625,44349,52795,43017,62214,46972,61353,36005,55815,55215,63898,35429,38891,31914,44830,49224,58095,39706,41084,60961,43371,40917,54975,19271,60769,55263,43798,47604,42069,34722,46567,54506,61725,43811,35081,53471,59435,34242,47543,61113,44558,34600,29289,55386,30704,37079,53858,53261,53071,40953,50469,60925,51478,60521,57731,42511,46852,58222,36054,31259,35496,61111,39485,45138,50168,45276,44816,44906,35543,37608,51353,47116,53520,34852,56854,47833,40162,41505,53128,34638,36009,33446,27675,52012,36257,35133,28509,48641,33563,36831,39509,56461,42589,50607,61187,54037,53652,62203,45251,61873,42466,50581,48374,36156,19069,50211,39459,33547,38545,46860,39976,53346,61453,43488,54284,47298,43680,31887,34771,33634,31188,50298,41326,39393,37929,45140,56416,60200,40950,57423,33232,31097,27990,56262,61056,32248,48810,27237,29370,52023,46809,52794,47911,30141,55599,59359,50611,39451,59730,50421,62764,54408,54545,43882,29934,28842,46012,30522,48255,37597,49769,45007,43053,41359,36742,38832,49773,50098,49888,30355,31466,36445,42488,43681,36796,42433,30612,43330,31389,30659,39007,38452,61362,28071,51842,32387,60120,34615,19404,30105,42227,37294,63319,33952,41910,54080,33626,39703,60149,61603,59458,54567,51491,29357,45301,62914,43701,35122,41095,39113,36895,52016,50571,38296,62831,62513,39443,56411,63093,47141,59571,35983,60243,60875,62141,33829,61088,41002,48175,60652,62359,50112,44154,52812,42036,61627,42213,46162,44586,47851,39102,61702,61920,49948,31994,50314,54496,51708,34146,60792,49830,56747,47569,42688,62804,54708,31079,56470,63801,46436,62590,54620,60518,42166,58667,53743,46029,45098,32246,56324,42052,56496,62889,62219,54051,49654,57571,45187,53087,53667,60416,51025,35593,59816,58342,60669,62891,47935,57369,45048,58627,45384,45427,44053,59555,59880,46084,34163,59717,50161,59803,57238,49954,45776,58549,44912,50307,50941,53296,46159,35088,57170,61149,37149,58968,46914,60339,30576,58021,45006,34835,52262,34916,45285,58419,54773,55332,58094,51133,57657,63192,41406,64063,52249,36655,62225,61757,58721,38957,45370,60498,43963,19026,38661,40034,31677,40720,51216,38365,41755,57737,52450,29359,47660,35855,33496,58744,54643,42006,47996,56770,60927,31314,61235,28470,32384,20580,37135,61752,43878,30847,41193,57591,59026,63022,62535,51956,52454,62275,40250,63187,62462,56712,46602,38142,36161,58329,59056,44009,38724,50152,50873,43743,35692,55507,39210,40258,63163,54523,61277,40112,51412,45792,42992,44456,55542,63078,54112,57280,43147,56703,56893,37250,47648,64402,36271,48045,49185,64027,48569,57349,63064,36432,35774,19465,22691,38940,33263,33616,61775,42950,42542,42034,62330,49702,51575,47859,58889,46278,43289,36382,55170,25958,63726,55470,31995,38335,38316,46452,23644,34201,55342,58926,44017,36915,44674,42071,35470,36621,46483,35686,36676,58186,50487,19023,48639,60744,19531,33757,48613,30728,42055,62661,62550,54786,55509,41439,56425,56898,50655,65391,50710,54525,49963,62897,50107,47843,52778,50541,39327,56947,37658,42462,35769,58217,60702,30598,33497,32011,50868,34591,59226,53401,59596,34607,44821,52309,38696,44025,47196,40265,50283,40502,58178,47117,45380,61413,33234,45169,28085,27928,35099,47755,31569,29420,38486,44061,55408,54061,43724,39023,35963,56765,39693,47692,46050,38162,32046,34845,35480,45978,40298,49508,41712,34527,63291,40830,61501,62820,38191,32573,33153,41804,49585,53329,38173,48127,47455,48414,56572,57814,54145,57524,35847,59119,48608,48820,57564,48173,31851,36699,45757,46074,27679,50846,30965,53453,56192,34870,35239,42758,34929,52328,41745,44277,50882,43329,57955,60065,59644,47999,58418,44965,51841,48433,25341,59237,52376,60212,57579,51753,46821,49497,62487,52691,61848,46555,60645,42472,39377,33785,48592,49718,58787,27791,47981,25992,42420,47637,41734,57869,39422,39329,56844,39993,57212,35793,38367,59370,59284,41060,29543,31276,59539,32852,33576,62710,48572,50002,57914,51117,40528,52554,38394,52411,48446,62161,53363,60335,60639,50238,39506,53747,45416,40707,52533,51684,61456,54737,54125,33622,58325,30912,43472,41044,52064,52292,31827,39322,42455,50257,60994,57356,62714,33200,47775,53633,47416,40204,32981,28521,50295,55389,49333,63483,51906,44311,56197,58420,41532,31085,48275,50709,62816,59038,37833,56918,31989,59297,48389,60334,42980,33632,39413,42088,56223,52036,61577,38378,54828,38214,41535,30512,46621,44801,47338,33225,41685,32200,28649,37011,37293,62196,63297,53129,44367,62424,43358,28328,50507,36551,35733,40597,40604,48689,19528,43185,45685,31205,52002,19529,40343,60779,52830,59289,32247,52978,47195,60221,59666,30863,62312,62353,48140,39672,32296,45820,61426,57799,61322,56400,42029,57509,60228,61497,49219,45114,53323,34420,60389,59201,58357,47804,60969,34973,46511,60861,31700,40941,60348,40459,50484,42581,54149,50457,36070,45807,43666,49987,31238,54407,57371,50028,44041,45399,49710,52349,44926,31235,31787,34884,53183,49344,62927,51566,50380,40615,47356,32633,56199,56443,34628,59616,32043,45209,50293,62980,33635,59266,59736,58062,27721,51325,40530,49242,38851,33492,41267,60319,60701,54101,52279,36510,51305,54732,39874,63304,29079,35538,32032,52644,38943,23515,41192,53420,50923,27353,28635,30535,48679,46061,37505,38481,56674,47344,39781,36506,35527,40079,44449,60131,43522,40321,31113,54840,52706,32047,34327,50029,44080,38782,60713,63783,47248,58561,36306,52892,34981,33638,63037,60081,51975,40674,62162,35565,45062,47330,36046,34738,57992,56297,47759,46644,57629,58530,62749,57274,57090,55400,56464,56441,59379,61257,62102,55853,55842,55843,63284,48347,41349,36848,48616,36921,41394,57936,61605,46616,44887,35577,59611,43306,46897,30955,41651,36709,45145,61428,44332,58269,40347,40064,34707,35589,39528,53491,51324,42016,61689,54700,31635,46759,56629,44675,49682,48130,32733,33831,30747,57617,57386,60002,30191,47556,49244,41972,60897,52257,62873,43456,56300,62670,30995,63315,62249,32596,63000,60005,31904,63050,58311,40031,62611,61985,61739,61496,61857,61876,52437,48159,50290,38016,56856,42702,51437,58708,60392,53732,49802,59731,45594,31588,49776,40699,58808,36565,42119,35803,63199,62630,36309,38533,54777,60502,31462,29995,36269,49441,50256,62691,46599,56521,53982,34539,30712,41121,40994,57269,37230,50981,54410,59900,46979,46851,30567,57604,45037,42971,40753,34248,48228,56766,47326,54852,49550,41255,35782,52911,51457,63100,62826,56249,52583,49938,57003,36483,63851,35879,42539,54516,31144,61204,51114,58657,57395,44612,50116,28218,57628,34513,53702,48437,42136,33875,54860,19249,40389,53844,42131,51639,34774,49685,53920,37764,36787,44888,35894,41644,57445,32874,58723,53480,44079,37322,39537,35744,34934,44856,57392,48911,48744,41355,34945,41580,30432,29343,31493,46448,44631,60980,27370,37412,56835,53186,53413,60295,62063,50144,31772,35938,29351,44307,50730,50840,50847,41783,49009,45259,38348,33918,54275,30962,59229,50815,32337,54134,24791,38505,50204,61461,48754,50027,43190,57257,62455,39903,49083,47733,51884,44040,42252,40689,33551,43686,53063,39757,52765,44935,53327,54257,53040,40388,37881,57638,53390,43486,43444,37677,44155,44641,33996,56792,51467,62230,37529,40760,62494,39397,62077,34566,50398,60574,62402,31130,60836,39063,45542,29348,34697,54531,44701,35785,35645,38199,34595,60767,42168,41813,51619,59761,42268,59632,59634,41984,31897,35835,51291,43538,59796,46285,34570,60181,54589,53574,35570,36584,37452,33641,51990,35204,38658,47206,55575,40778,44664,48896,35261,56450,43829,53271,39844,42054,42727,48750,54164,40652,27516,51429,42128,35010,52233,41853,43544,38611,40666,49186,56764,39241,44056,42126,53059,34167,53386,62231,31506,48948,60979,61320,31622,57424,45265,40017,56410,40108,47227,51680,33317,49656,54246,19408,39668,61337,44898,49016,40116,52412,51341,51345,36385,35749,39508,40972,40668,54019,40256,63753,60231,31271,51856,37850,62851,62030,57832,54180,47906,47632,59406,34582,29595,28700,28055,29842,43431,47400,59978,59714,57321,52833,35537,45385,58104,44519,32760,49803,55240,42005,30515,59988,54738,36188,49562,39374,30843,35034,39704,57999,54269,36158,33278,35458,42547,37189,62881,30790,40111,48660,58162,44231,57373,50521,56811,45994,60072,51870,53444,59979,46034,50506,35416,57341,35901,36994,51751,53013,60220,51177,47124,62948,38209,56921,43198,48506,49876,30507,31319,41104,46990,46310,60471,62999,30254,50416,50213,39754,58979,58601,58050,52210,57359,43547,56331,56186,34578,44417,19012,49358,42292,48472,42744,42775,60506,49160,31895,45693,45414,41315,54467,52736,45950,36126,28686,40702,34798,49949,62654,60240,43862,29818,45956,54675,38047,36943,42732,39157,51118,63149,50580,47235,31740,62156,63169,56545,56831,48447,63110,60611,42666,32309,34848,37676,57908,58031,40417,32015,40756,63107,59953,50590,61749,46677,41489,61881,56408,19125,47184,62241,35526,51106,50837,44396,50576,31654,58069,52362,52418,51385,51357,51343,42963,61251,46715,46819,54072,46495,53290,48361,57484,49956,36830,42667,51299,49722,45298,51874,39675,43127,57054,62824,57589,57514,62840,33378,58971,48936,54262,44005,57812,40960,64995,62406,42568,54085,48774,57721,31290,52298,59854,48281,29738,41297,51072,44460,36916,47876,40121,34560,51835,32718,45160,47946,42485,44791,51206,58061,61295,38236,56871,30801,51040,54394,58362,36624,51502,46818,46811,43295,49170,34625,52055,49182,34623,51517,62321,50741,42174,38633,56800,38769,33876,35518,46824,38281,35524,54320,32025,45084,46455,43308,47787,33562,51339,53576,58930,38778,43014,53902,64496,39040,48097,52281,28640,33822,47262,62072,34725,47830,32190,48851,27677,36618,58188,34182,60450,35998,40067,41098,60377,54341,57190,53164,64501,46364,36095,62071,19067,19367,35732,43211,37932,40796,34613,53499,49768,33976,61391,47343,42106,42669,61205,36850,50338,52366,40984,38337,41995,31598,21273,50699,52386,48124,43250,48242,50073,31812,53449,32119,53896,60047,59521,52969,46493,62337,28574,42579,29241,31707,57803,50481,44290,46883,19511,54225,24650,56499,49727,58202,33472,59199,50236,40826,39115,42664,44227,57851,44853,57910,63468,33761,38035,28130,32826,53970,62834,61406,53740,44239,56264,41526,61214,53143,34657,61829,32775,38976,42475,38805,39095,53729,31475,38372,19442,30113,44985,44516,46498,47536,39055,46876,57699,61789,45139,38351,43276,58015,38469,39724,19578,50394,31463,40758,39813,39920,57117,48040,43892,34616,54474,54224,38330,36007,45397,19066,19138,37309,33583,50106,29996,37928,19002,31856,36092,37399,34912,51347,51729,40657,62166,29761,41820,36577,50129,45410,43194,41653,50183,42150,37511,38756,35550,39577,47774,41239,26587,55369,19095,53368,39432,41087,29671,50351,37510,35703,36314,40478,41183,50103,35641,35919,34520,38347,47742,35614,37894,39197,34594,48319,42452,19593,51382,35057,56194,37098,51593,61927,37513,19020,18998,19022,19013,32030,57599,57941,57426,42978,29604,40531,40700,38772,50324,40879,45793,38740,40612,40501,50836,53415,56526,43694,53034,46936,41862,44216,60127,39071,35892,39661,55426,48169,31190,52979,42691,41112,57474,57477,57788,46163,19257,40683,35022,34998,45618,47573,44316,49737,39396,51518,43804,35113,38844,57136,41787,52011,36074,57004,58747,62473,41351,59563,38144,29381,47189,19411,39783,37730,51262,44404,47406,52416,62972,54671,40932,53700,46373,19203,43498,63109,49423,50438,45975,62357,19242,19423,19399,19421,47890,39515,33449,52719,57019,61009,35358,58340,31452,42259,34721,46952,19558,42241,34138,46545,46003,47822,34590,54182,44028,62706,35897,42228,50854,54128,43532,52096,51738,58573,47657,53313,57412,44109,58192,40774,59944,29933,62138,58113,18996,53066,48629,53008,58931,49920,60982,38264,19361,32041,40923,38979,54259,53326,59901,41786,35566,62607,25894,62109,44362,46605,32412,40880,36010,47778,42617,37545,49732,31963,45277,60608,35965,19372,33751,47239,36448,40058,19245,35285,62270,48426,39131,35557,42258,35304)
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


	# save user first name as nickname, if we have them as users in Drupal
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, 'nickname' as meta_key, pv.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv ON u.uid = pv.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf ON pv.fid = pf.fid
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf.fid = 4
	;


	# update user display name to "first last"
	UPDATE `minnpost.wordpress`.wp_users u
		JOIN `minnpost.wordpress`.wp_usermeta m ON u.ID = m.user_id
		SET u.display_name = CONCAT(m.meta_value)
		WHERE m.meta_key = 'first_name' AND m.meta_value IS NOT NULL
	;

	UPDATE `minnpost.wordpress`.wp_users u
		JOIN `minnpost.wordpress`.wp_usermeta m ON u.ID = m.user_id
		SET u.display_name = CONCAT(u.display_name, ' ', m.meta_value)
		WHERE m.meta_key = 'last_name' AND m.meta_value IS NOT NULL
	;

	UPDATE `minnpost.wordpress`.wp_users u
		SET u.display_name = u.user_nicename
		WHERE u.display_name IS NULL OR u.display_name = ''
	;


	# Drupal authors who may or may not be users
	# these get inserted as posts with a type of guest-author, for the plugin
	# this one does take the vid into account (we do track revisions)
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_modified_gmt, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			n.title `post_title`,
			'' `post_excerpt`,
			CONCAT('cap-', substring_index(a.dst, '/', -1)) `post_name`,
			'' `to_ping`,
			'' `pinged`,
			FROM_UNIXTIME(n.changed) `post_modified`,
			CONVERT_TZ(FROM_UNIXTIME(n.changed), 'America/Chicago', 'UTC') `post_modified_gmt`,
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
		`name` varchar(200) NOT NULL DEFAULT '',
		`slug` varchar(200) NOT NULL DEFAULT '',
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
		SELECT t.term_id, 'author', CONCAT(p.post_title, ' ', t.name, ' ', p.ID) as description
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
		(id, post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type)
		SELECT DISTINCT
			n2.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
			WHERE n.type != 'event'
	;


	# insert main event images as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/events', '/imagecache/article_detail/images/events')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_main_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_main_image_fid = f.fid
			WHERE n.type = 'event'
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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


	# insert partner logo images as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/partner-logos', '/imagecache/article_inset/partner-logos')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner p using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON p.field_logo_fid = f.fid
			WHERE n.type = 'partner'
	;


	# post id for partner offer image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_partner_logo_image_id' `meta_key`,
			p.ID `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			INNER JOIN `minnpost.wordpress`.wp_posts parent ON p.post_parent = parent.ID
			WHERE p.post_type = 'attachment' and parent.post_type = 'partner'
	;


	# url for partner offer image
	# have to use that temp file id field
	# this doesn't need vid because it joins with the wordpress image post already
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			p.post_parent `post_id`,
			'_mp_partner_logo_image' `meta_key`,
			p.guid `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			INNER JOIN `minnpost.drupal`.files f ON p.image_post_file_id_old = f.fid
			INNER JOIN `minnpost.wordpress`.wp_posts parent ON p.post_parent = parent.ID
			WHERE p.post_type = 'attachment' and parent.post_type = 'partner'
	;


	# we shouldn't need to null the temp value because it all comes from drupal's files table


	# insert post thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
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
			INNER JOIN `minnpost.drupal`.content_type_slideshow s USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON s.field_op_slideshow_thumb_fid = f.fid
	;


	# insert sponsor thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', f.filepath) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_image_thumbnail i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_image_thumbnail_fid = f.fid
			WHERE n.type = 'sponsor'
	;


	# insert event thumbnails as posts
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			n.nid `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/events', '/imagefield_thumbs/images/thumbnails/events')) `guid`,
			'attachment' `post_type`,
			f.filemime `post_mime_type`,
			f.fid `image_post_file_id_old`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)			
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/events%'
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
	# these need to match the size names in the theme. ours are at minnpost-largo/inc/uploads.php in the minnpost_image_sizes function


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
			'_mp_post_thumbnail_image_feature-large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-medium' `meta_key`,
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
			'_mp_post_thumbnail_image_newsletter-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_author-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-medium' `meta_key`,
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
			'_mp_post_thumbnail_image_newsletter-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_author-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-medium' `meta_key`,
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
			'_mp_post_thumbnail_image_newsletter-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_author-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-large' `meta_key`,
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
			'_mp_post_thumbnail_image_feature-medium' `meta_key`,
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
			'_mp_post_thumbnail_image_newsletter-thumbnail' `meta_key`,
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
			'_mp_post_thumbnail_image_author-thumbnail' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/author_teaser/images/thumbnails/video')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_video v USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON v.field_op_video_thumbnail_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/video%'
	;


	# there is no /feature/images/thumbnails/slideshow


	# teaser image for authors themselves
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_author_image_author-teaser' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/author', '/imagecache/author_teaser/images/author')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_author_photo_fid = f.fid
			WHERE f.filepath LIKE '%images/author%'
	;


	# thumbnail image for authors themselves
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_author_image_author-thumbnail' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/author', '/imagecache/thumbnail/images/author')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a USING (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON a.field_author_photo_fid = f.fid
			WHERE f.filepath LIKE '%images/author%'
	;


	# for events

	# feature thumbnail for event posts
	# this is the larger thumbnail image that shows on section pages from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/events', '/imagecache/feature/images/thumbnails/events')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/events%'
	;


	# feature large does not get created for events


	# feature middle thumbnail for event posts
	# this is the middle thumbnail image that shows on the homepage from cache folder
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_feature-medium' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/events', '/imagecache/feature_middle/images/thumbnails/events')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/events%'
	;


	# newsletter thumbnail
	# this is the thumbnail image that shows on newsletters
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_newsletter-thumbnail' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/events', '/imagecache/newsletter_thumb/images/thumbnails/events')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/events%'
	;


	# author teaser thumbnail for event
	# this gets used on that recent stories widget, at least
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'_mp_post_thumbnail_image_author-thumbnail' `meta_key`,
			CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/events', '/imagecache/author_teaser/images/thumbnails/events')) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_thumbnail_image i using (nid, vid)
			INNER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
			WHERE f.filepath LIKE '%images/thumbnails/events%'
	;


	# todo: we need to figure out whether and how to handle duplicate meta_keys for the same post
	# but with conflicting values
	# i know that at least sometimes the url is the same; it's being added more than once somehow. this may just not be a problem though.



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


	# insert metadata for post thumbnails - this relates to the image post ID - this will also get event data
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


	# insert metadata for partner offer images - related to image post id
	# this doesn't really seem to need any vid stuff
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
		ID `post_id`,
		'_wp_imported_metadata' `meta_key`,
		p.field_logo_data `meta_value`
		FROM `minnpost.wordpress`.wp_posts p
		LEFT OUTER JOIN `minnpost.drupal`.content_type_partner p ON p.post_parent = p.nid
		WHERE post_type = 'attachment' AND p.field_logo_fid IS NOT NULL
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
		SET meta_value = 'feature-medium'
		WHERE meta_value = 'medium' AND meta_key = '_mp_post_homepage_image_size'
	;

	# large
	UPDATE `minnpost.wordpress`.wp_postmeta
		SET meta_value = 'feature-large'
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



# Section 7 - Core Post Metadata. Now the order needs to come after authors, at least.

	# core post text/wysiwyg/etc fields

	# whether to use html editor
	# this one does not need vid because it's just wordpress
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				p.ID `post_id`,
				'_mp_post_use_html_editor' as meta_key,
				'on' as meta_value
			FROM `minnpost.wordpress`.wp_posts p
			WHERE post_content LIKE '%[raw shortcodes=1]%'
	;

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


	# sidebar field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				s.nid `post_id`,
				'_mp_post_sidebar' as meta_key,
				s.field_sidebar_value as `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_sidebar s USING(nid, vid)
			WHERE s.field_sidebar_value IS NOT NULL
	;


	# set the remove sidebar field for article_full posts
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_remove_right_sidebar' as meta_key,
				'on' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			WHERE n.type = 'article_full'
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


	# if the constraint fails, do this
	#DELETE t1 FROM `wp_postmeta` t1, `wp_postmeta` t2 WHERE t1.meta_id > t2.meta_id AND t1.post_id = t2.post_id AND t1.meta_key = t2.meta_key AND t1.meta_value = t2.meta_value
	#;


	# newsletter preview text field
	# this one does take the vid into account
	# note: this field currently does not exist in any newsletters, so it will error unless someone uses it
	#INSERT INTO `minnpost.wordpress`.wp_postmeta
	#	(post_id, meta_key, meta_value)
	#	SELECT DISTINCT
	#			p.nid `post_id`,
	#			'_mp_newsletter_preview_text' as meta_key,
	#			p.field_preview_value `meta_value`
	#		FROM `minnpost.drupal`.node n
	#		INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
	#		INNER JOIN `minnpost.drupal`.content_field_preview_text p USING(nid, vid)
	#		WHERE p.field_preview_value IS NOT NULL
	#;


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


	# sponsor fields

	# url field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				u.nid `post_id`,
				'cr3ativ_sponsorurl' as meta_key,
				u.field_url_url `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_url u USING(nid, vid)
			WHERE u.field_url_url IS NOT NULL AND n.type = 'sponsor'
	;


	# fix on-site sponsor urls
	UPDATE `minnpost.wordpress`.wp_postmeta
		SET meta_value = CONCAT('https://www.minnpost.com/', meta_value)
		WHERE meta_key = 'cr3ativ_sponsorurl' AND meta_value NOT LIKE 'http%'
	;


	# display text field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				d.nid `post_id`,
				'cr3ativ_sponsortext' as meta_key,
				d.field_display_title_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_display_title d USING(nid, vid)
			WHERE d.field_display_title_value IS NOT NULL AND n.type = 'sponsor'
	;


	# related content fields


	# if there is multimedia content, turn the show related field on
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_show_related_content' as meta_key, 'on' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_related_mmedia m USING(nid, vid)
			INNER JOIN `minnpost.drupal`.node n2 ON n2.nid = m.field_op_related_mmedia_nid
			WHERE field_op_related_mmedia_nid IS NOT NULL AND n2.type IN ('article', 'article_full', 'audio', 'event', 'newsletter', 'page', 'video', 'slideshow', 'sponsor')
			GROUP BY n.nid, n.vid
	;


	# if there is related content, turn the show related field on
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_show_related_content' as meta_key, 'on' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_related_content c USING(nid, vid)
			INNER JOIN `minnpost.drupal`.node n2 ON n2.nid = c.field_related_content_nid
			WHERE field_related_content_nid IS NOT NULL AND n2.type IN ('article', 'article_full', 'audio', 'event', 'newsletter', 'page', 'video', 'slideshow', 'sponsor')
			GROUP BY n.nid, n.vid
	;


	# related multimedia field
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_related_multimedia' as meta_key, GROUP_CONCAT(DISTINCT n2.nid ORDER BY m.delta ASC) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_related_mmedia m USING(nid, vid)
			INNER JOIN `minnpost.drupal`.node n2 ON n2.nid = m.field_op_related_mmedia_nid
			WHERE field_op_related_mmedia_nid IS NOT NULL AND n2.type IN ('article', 'article_full', 'audio', 'event', 'newsletter', 'page', 'video', 'slideshow', 'sponsor')
			GROUP BY n.nid, n.vid
	;


	# related content field
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_mp_related_content' as meta_key, GROUP_CONCAT(DISTINCT n2.nid ORDER BY c.delta ASC) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_related_content c USING(nid, vid)
			INNER JOIN `minnpost.drupal`.node n2 ON n2.nid = c.field_related_content_nid
			WHERE c.field_related_content_nid IS NOT NULL AND n2.type IN ('article', 'article_full', 'audio', 'event', 'newsletter', 'page', 'video', 'slideshow', 'sponsor')
			GROUP BY n.nid, n.vid 
	;


	# event fields

	# start date
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_EventStartDate' as meta_key, e.field_event_date_value as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_event e USING(nid, vid)
			GROUP BY nid, vid
	;

	# end date
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_EventEndDate' as meta_key, e.field_event_date_value2 as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_event e USING(nid, vid)
			GROUP BY nid, vid
	;

	# event timezone
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_EventTimezone' as meta_key, 'America/Chicago' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_event e USING(nid, vid)
			GROUP BY nid, vid
	;


	# event timezone abbr
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_EventTimezoneAbbr' as meta_key, 'CST' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_event e USING(nid, vid)
			GROUP BY nid, vid
	;


	# event origin
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT n.nid as post_id, '_EventOrigin' as meta_key, 'events-calendar' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_event e USING(nid, vid)
			GROUP BY nid, vid
	;


	# add concatenated member levels
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_access_level' as meta_key,
				GROUP_CONCAT(a.field_minnpost_access_value) as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_minnpost_access a USING(nid, vid)
			WHERE a.field_minnpost_access_value IS NOT NULL
			GROUP BY nid, vid
	;


	# member level for bronze content
	UPDATE wp_postmeta
		SET meta_value = 1
		WHERE meta_key = '_access_level' AND meta_value = 'Bronze,Silver,Gold,Platinum'
	;


	# member level for silver content
	UPDATE wp_postmeta
		SET meta_value = 2
		WHERE meta_key = '_access_level' AND meta_value = 'Silver,Gold,Platinum'
	;

	UPDATE wp_postmeta
		SET meta_value = 2
		WHERE meta_key = '_access_level' AND meta_value = 'Silver,Platinum'
	;

	UPDATE wp_postmeta
		SET meta_value = 2
		WHERE meta_key = '_access_level' AND meta_value = 'Silver'
	;


	# member level for gold content
	UPDATE wp_postmeta
		SET meta_value = 3
		WHERE meta_key = '_access_level' AND meta_value = 'Gold,Platinum'
	;


	# member level for platinum content
	UPDATE wp_postmeta
		SET meta_value = 4
		WHERE meta_key = '_access_level' AND meta_value = 'Platinum'
	;


	# mp+ icon style
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				a.nid `post_id`,
				'_mp_plus_icon_style' as meta_key,
				a.field_minnpost_plus_icon_style_value as `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_article a USING(nid, vid)
			WHERE a.field_minnpost_plus_icon_style_value IS NOT NULL
	;


	# fields for partners, partner offers, partner offer instances

	# partner link url
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				p.nid `post_id`,
				'_mp_partner_link_url' as meta_key,
				p.field_link_url_url as `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner p USING(nid, vid)
			WHERE p.field_link_url_url IS NOT NULL
	;


	# Remove author display from posts with no specified author. co-authors plus will set the user to the author by default, but we don't want this to display if we haven't told it to
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT n.nid `post_id`,
			'_mp_remove_author_from_display' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_author a USING(nid, vid)
			WHERE a.field_op_author_nid IS NULL
			GROUP BY n.nid, n.vid
	;


	# Remove date display from posts with no specified author because if there's no author on old posts, i think we probably don't want to show the date either
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT n.nid `post_id`,
			'_mp_remove_date_from_display' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_author a USING(nid, vid)
			WHERE a.field_op_author_nid IS NULL
			GROUP BY n.nid, n.vid
	;


	# Remove category display from posts with no specified author because if there's no author on old posts, i think we probably don't want to show the category either
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT n.nid `post_id`,
			'_mp_remove_category_from_display' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_author a USING(nid, vid)
			WHERE a.field_op_author_nid IS NULL
			GROUP BY n.nid, n.vid
	;


	# remove all three of those meta values from posts that have a byline field
	# this one does take the vid into account
	DELETE FROM `minnpost.wordpress`.wp_postmeta
  		WHERE meta_key IN ('_mp_remove_author_from_display', '_mp_remove_date_from_display', '_mp_remove_category_from_display') AND post_id IN (
    		SELECT DISTINCT
				b.nid `post_id`
				FROM `minnpost.drupal`.node n
				INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
				INNER JOIN `minnpost.drupal`.content_field_byline b USING(nid, vid)
				WHERE b.field_byline_value IS NOT NULL
				GROUP BY n.nid, n.vid
  		)
  	;


	# Text to replace the category display
	# for sure, we at least need the sponsor pages with their "Why We Care" thing
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT p.ID `post_id`,
			'_mp_replace_category_text' `meta_key`,
			'Why We Care' `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			WHERE post_content LIKE '%<div class="mp_classification clear-block"><div class="breadcrumb">Why We Care</div></div>%'
	;


	# by default, we should have no automatic ads on full_page_articles from drupal
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT n.nid `post_id`,
			'_mp_prevent_automatic_ads' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.wordpress`.wp_posts p ON p.ID = n.nid
			WHERE n.type = 'article_full'
			GROUP BY nid, vid
	;


	# by default, we should hide newsletter signup on full_page_articles
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT n.nid `post_id`,
			'_mp_remove_newsletter_signup_from_display' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.wordpress`.wp_posts p ON p.ID = n.nid
			WHERE n.type = 'article_full'
			GROUP BY nid, vid
	;


	# popup settings field
	# add concatenated member levels
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
			n.nid `post_id`,
			'popup_settings' as meta_key,
			CONCAT('a:32:{s:19:"disable_form_reopen";b:0;s:17:"disable_on_mobile";b:0;s:17:"disable_on_tablet";b:0;s:18:"custom_height_auto";s:1:"1";s:18:"scrollable_content";b:0;s:21:"position_from_trigger";b:0;s:14:"position_fixed";s:1:"1";s:16:"overlay_disabled";s:1:"1";s:9:"stackable";b:0;s:18:"disable_reposition";b:0;s:22:"close_on_overlay_click";s:1:"1";s:18:"close_on_esc_press";s:1:"1";s:17:"close_on_f4_press";s:1:"1";s:8:"triggers";a:1:{i:0;a:2:{s:4:"type";s:9:"auto_open";s:8:"settings";a:2:{s:11:"cookie_name";s:25:"minnpost-popup-last-shown";s:5:"delay";s:3:"500";}}}s:7:"cookies";a:1:{i:0;a:2:{s:5:"event";s:13:"on_popup_open";s:8:"settings";a:5:{s:4:"name";s:25:"minnpost-popup-last-shown";s:3:"key";s:0:"";s:7:"session";s:0:"";s:4:"time";s:',
				char_length(CONCAT(m.field_mpdm_timeout_value, ' hours')),
				':"',
				m.field_mpdm_timeout_value,
				' hours";s:4:"path";s:1:"1";}}}s:8:"theme_id";s:6:"157583";s:4:"size";s:6:"custom";s:20:"responsive_min_width";s:2:"0%";s:20:"responsive_max_width";s:4:"100%";s:12:"custom_width";s:3:"95%";s:13:"custom_height";s:5:"380px";s:14:"animation_type";s:4:"fade";s:15:"animation_speed";s:3:"350";s:16:"animation_origin";s:10:"center top";s:8:"location";s:13:"center bottom";s:12:"position_top";s:3:"100";s:15:"position_bottom";s:1:"0";s:13:"position_left";s:1:"0";s:14:"position_right";s:1:"0";s:6:"zindex";s:10:"1999999999";s:10:"close_text";s:1:"x";s:18:"close_button_delay";s:1:"0";}'
			) as meta_value 
		FROM
			`minnpost.drupal`.node n 
			INNER JOIN
				`minnpost.drupal`.node_revisions r USING(nid, vid) 
			INNER JOIN
				`minnpost.drupal`.content_type_mpdm_message m 
				ON n.nid = m.nid 
			INNER JOIN
				`minnpost.drupal`.content_field_mpdm_hide h 
				ON n.nid = h.nid 
			INNER JOIN
				`minnpost.drupal`.content_field_mpdm_visibility v 
				ON n.nid = v.nid 
		WHERE
			m.field_mpdm_type_value = 'bottom' 
		GROUP BY
			n.nid,
			n.vid
	;


	# partner offer title
	UPDATE `minnpost.wordpress`.wp_posts p
		INNER JOIN (
			SELECT
				n.nid as id,
				offer.field_event_value as post_title
				FROM `minnpost.drupal`.node n
				INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
				INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
				WHERE n.type = 'partner_offer'
			) as event_value on p.ID = event_value.id
		SET p.post_title = event_value.post_title
	;


	# partner offer partner field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'partner_id' as meta_key,
				offer.field_partner_nid `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_partner_nid IS NOT NULL
	;


	# partner offer quantity field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_quantity' as meta_key,
				offer.field_quantity_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_quantity_value IS NOT NULL
	;


	# partner offer type field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_type' as meta_key,
				offer.field_type_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_type_value IS NOT NULL
	;


	# partner offer restriction field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_restriction' as meta_key,
				offer.field_restriction_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_restriction_value IS NOT NULL
	;

	# partner offer more info text field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_more_info_text' as meta_key,
				offer.field_more_info_text_value `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_more_info_text_value IS NOT NULL
	;


	# partner offer more info url field
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_more_info_url' as meta_key,
				offer.field_more_info_url_url `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_more_info_url_url IS NOT NULL
	;


	# partner offer claimable start date
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_claimable_start_date' as meta_key,
				UNIX_TIMESTAMP(offer.field_offer_claimable_dates_value) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_offer_claimable_dates_value IS NOT NULL
	;


	# partner offer claimable end date
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT DISTINCT
				n.nid `post_id`,
				'_mp_partner_offer_claimable_end_date' as meta_key,
				UNIX_TIMESTAMP(offer.field_offer_claimable_dates_value2) `meta_value`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_partner_offer offer USING(nid, vid)
			WHERE offer.field_offer_claimable_dates_value2 IS NOT NULL
	;


	# partner offer instances field
	# this one does take the vid into account
	SET SESSION group_concat_max_len = 10000000000;
	SET @x:=0;
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(post_id, meta_key, meta_value)
		SELECT
			instance.field_partner_offer_nid as post_id, '_mp_partner_offer_instance' as meta_key, CONCAT('a:',totals.count,':{',value,'}') as meta_value
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_type_partner_offer_instance instance USING (nid, vid),
		(
			SELECT nid, COUNT(*) as count, GROUP_CONCAT('i:', (@x:=@x+1) - 1,';a:4:{s:34:"_mp_partner_offer_instance_enabled";s:2:"on";s:31:"_mp_partner_offer_instance_date";', IF(LENGTH(field_redeem_dates_value)>0, CONCAT('i:', REPLACE(UNIX_TIMESTAMP(field_redeem_dates_value), '.000000', '')), 's:0:""'), ';s:30:"_mp_partner_offer_claimed_date";', IF(LENGTH(field_claimed_value)>0, CONCAT('i:', field_claimed_value), 's:0:""'), ';s:28:"_mp_partner_offer_claim_user";a:2:{s:4:"name";s:', IF(LENGTH(users.display_name)>0, char_length(users.display_name), 0), ':"', IF(LENGTH(users.display_name)>0, users.display_name, ''), '";s:2:"id";s:', IF(LENGTH(users.ID)>0, char_length(users.ID), 0), ':"', IF(LENGTH(users.ID)>0, users.ID, ''), '";}}' SEPARATOR '') as value,@x:=0
			FROM `minnpost.drupal`.content_type_partner_offer_instance
			LEFT OUTER JOIN `minnpost.wordpress`.wp_users users ON content_type_partner_offer_instance.field_user_uid = users.ID
			GROUP BY nid
		) AS totals
		WHERE n.nid = totals.nid
		GROUP BY post_id
	;



# Section 8 - Categories, their images, text fields, taxonomies, and their relationships to posts. The order doesn't matter here. We can skip this section if we're testing other stuff (we use the old id field to keep stuff together)

	# this category stuff by default breaks because the term ID has already been used - by the tag instead of the category
	# it fails to add the duplicate IDs because Drupal has them in separate tables
	# we fix this by temporarily using a term_id_old field to track the relationships
	# this term_id_old field gets used to assign each category to:
	# 1. its custom text fields
	# 2. its relationships to posts
	# 3. its taxonomy rows


	# add the term_id_old field for tracking Drupal term IDs
	ALTER TABLE `minnpost.wordpress`.wp_terms ADD term_id_old BIGINT(20);


	# Temporary table for department terms
	CREATE TABLE `minnpost.wordpress`.`wp_terms_dept` (
		`term_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`name` varchar(200) NOT NULL DEFAULT '',
		`slug` varchar(200) NOT NULL DEFAULT '',
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


	# we need to put the sections in as departments also, because they show up in the list and are sometimes used that way
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_dept (term_id, name, slug)
		SELECT nid `term_id`,
		n.title `name`,
		substring_index(a.dst, '/', -1) `slug`
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			LEFT OUTER JOIN `minnpost.drupal`.url_alias a ON a.src = CONCAT('node/', n.nid)
			WHERE n.type='section'
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


	# content link field - this does not go into the wordpress ui because it is so rarely used in drupal
	# this one does take the vid into account
	INSERT INTO `minnpost.wordpress`.wp_termmeta
		(term_id, meta_key, meta_value)
		SELECT DISTINCT term.term_id as `term_id`, '_mp_category_excerpt_links' as meta_key, CONCAT('a:2:{s:3:"url";', CONCAT('s:', char_length(m.field_link_multiple_url), ':"'), m.field_link_multiple_url, '";s:4:"text";', CONCAT('s:', char_length(m.field_link_multiple_title), ':"'), m.field_link_multiple_title, '";}') `meta_value`
			FROM wp_term_taxonomy tax
				INNER JOIN wp_terms term ON tax.term_id = term.term_id
				INNER JOIN `minnpost.drupal`.content_field_department dept ON term.term_id_old = dept.field_department_nid
				INNER JOIN `minnpost.drupal`.node n ON dept.field_department_nid = n.nid
				INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
				INNER JOIN `minnpost.drupal`.content_field_link_multiple m ON m.nid = n.nid AND m.vid = n.vid
				WHERE tax.taxonomy = 'category' AND n.type = 'department' AND m.field_link_multiple_url IS NOT NULL AND m.field_link_multiple_url != ''
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
		`featured_terms` varchar(200) NOT NULL DEFAULT ''
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old, term_id)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			term.term_id `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(REPLACE(f.filepath, '/images/department', '/imagecache/feature/images/department'), '/images', '/imagecache/feature/images')) `guid`,
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
		(post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, post_status, post_parent, guid, post_type, post_mime_type, image_post_file_id_old, term_id)
		SELECT DISTINCT
			n.uid `post_author`,
			FROM_UNIXTIME(f.timestamp) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			'' `post_content`,
			f.filename `post_title`,
			'' `post_excerpt`,
			f.filename `post_name`,
			'inherit' `post_status`,
			'0' `post_parent`,
			CONCAT('https://www.minnpost.com/', REPLACE(REPLACE(f.filepath, '/images/thumbnails/department', '/imagecache/thumbnail/images/thumbnails/department'), '/images/thumbnails', '/imagecache/thumbnail/images/thumbnails')) `guid`,
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
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL AND f.filepath LIKE '%thumbnail%'
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
			WHERE p.post_type = 'attachment' AND term_id IS NOT NULL AND f.filepath LIKE '%thumbnail%'
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


	# temporary table for categories listed on the columns page
	CREATE TABLE `column_ids` (
		`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
		`post_id` int(11) NOT NULL,
		`term_ids` text NOT NULL,
		PRIMARY KEY (`id`)
	);


	# put the columns listed on that page into the table
	INSERT INTO `minnpost.wordpress`.column_ids
		(post_id, term_ids)
		SELECT ID `post_id`, GROUP_CONCAT(term_id ORDER BY n2.title) `term_ids`
			FROM `minnpost.wordpress`.wp_posts p
				INNER JOIN `minnpost.drupal`.node n ON p.ID = n.nid
				INNER JOIN `minnpost.drupal`.node_revisions nr ON n.nid = nr.nid AND n.vid = nr.vid
				INNER JOIN `minnpost.drupal`.content_field_rel_feature f ON n.nid = f.nid AND n.vid = f.vid
				INNER JOIN `minnpost.drupal`.node n2 ON f.field_rel_feature_nid = n2.nid
				INNER JOIN `minnpost.wordpress`.wp_terms t ON f.field_rel_feature_nid = t.term_id_old
				WHERE post_title = 'Columns'
				GROUP BY ID
	;


	# append shortcode for columns to the page
	UPDATE `minnpost.wordpress`.wp_posts
		JOIN `minnpost.wordpress`.column_ids
		ON wp_posts.ID = column_ids.post_id
		SET wp_posts.post_content = CONCAT('<div class="a-page-info">', wp_posts.post_content, '</div><!--break-->[column_list term_ids="', column_ids.term_ids, '"]')
	;


	# get rid of that temporary column id table
	DROP TABLE column_ids;


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
		`name` varchar(200) NOT NULL DEFAULT '',
		`slug` varchar(200) NOT NULL DEFAULT '',
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


	# Update the term table with the section node id in the old id field for tracking relationships
	UPDATE `minnpost.wordpress`.wp_terms t JOIN `minnpost.wordpress`.wp_terms_section s ON t.name = s.name
		SET t.term_id_old = s.term_id
	;


	# Create an event taxonomy for each section
	INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy, description)
		SELECT term_id, 'tribe_events_cat', '' FROM wp_terms WHERE term_id_old IS NOT NULL
	;


	# cleanup term duplicates


	# Delete duplicates for terms that share the same taxonomy
	DELETE FROM `minnpost.wordpress`.wp_terms
  		WHERE term_id NOT IN (
    		SELECT * FROM (
      			SELECT MAX(t.term_id)
      			FROM `minnpost.wordpress`.wp_terms t
      			INNER JOIN wp_term_taxonomy tax ON t.term_id = tax.term_id
        		GROUP BY slug, taxonomy
    		) 
  		x)
  	;


	# Create relationships for each story to the section it had in Drupal
	# Track this relationship by the term_id_old field
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
		SELECT DISTINCT section.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
			FROM wp_term_taxonomy tax
				INNER JOIN wp_terms term ON tax.term_id = term.term_id
				INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
				INNER JOIN `minnpost.drupal`.node n ON section.nid = n.nid AND section.vid = n.vid
				INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
				WHERE tax.taxonomy = 'category' AND n.type != 'event'
	;


	# Create relationships for each event to the section it had in Drupal
	# Track this relationship by the term_id_old field
	# this one does take the vid into account
	INSERT IGNORE INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
		SELECT DISTINCT section.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
			FROM wp_term_taxonomy tax
				INNER JOIN wp_terms term ON tax.term_id = term.term_id
				INNER JOIN `minnpost.drupal`.content_field_section section ON term.term_id_old = section.field_section_nid
				INNER JOIN `minnpost.drupal`.node n ON section.nid = n.nid AND section.vid = n.vid
				INNER JOIN `minnpost.drupal`.node_revisions nr ON nr.nid = n.nid AND nr.vid = n.vid
				WHERE tax.taxonomy = 'tribe_events_cat' AND n.type = 'event'
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
	# mp change: keep the value for homepage 200 characters or less
	# this doesn't really seem to need any vid stuff
	INSERT INTO `minnpost.wordpress`.wp_comments
		(comment_ID, comment_post_ID, comment_date, comment_content, comment_parent, comment_author,
		comment_author_email, comment_author_url, comment_approved, user_id)
		SELECT DISTINCT
			cid, nid, FROM_UNIXTIME(timestamp), comment, pid, name,
			mail, SUBSTRING(homepage, 1, 200), IF(status=1, 'trash', 1), uid
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


	# prepend the comment with the subject from drupal if it is not the same as the start of the comment
	UPDATE `minnpost.wordpress`.wp_comments
		JOIN `minnpost.drupal`.comments
		ON `minnpost.wordpress`.wp_comments.comment_ID = `minnpost.drupal`.comments.cid
		SET `minnpost.wordpress`.wp_comments.comment_content = CONCAT('<p class="a-comment-drupal-subject">', `minnpost.drupal`.comments.subject, '</p>', `minnpost.wordpress`.wp_comments.comment_content)
		WHERE `minnpost.drupal`.comments.subject != '' AND REPLACE(`minnpost.wordpress`.wp_comments.comment_content, '<p>', '') NOT LIKE CONCAT(`minnpost.drupal`.comments.subject, '%')
	;



# Section 10 - User and Author Metadata. Order needs to be after users/authors (#4). We can skip this section if we're testing other stuff.

	# user permissions

	# when we add multiple permissions per user, it is fixed by the Merge Serialized Fields plugin.

	# add banned users who cannot comment
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"banned";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('authenticated noncommenting user')
		)
	;


	# Sets bronze member level capabilities for members
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:13:"member_bronze";s:1:"1";}' as meta_value
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
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:13:"member_silver";s:1:"1";}' as meta_value
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
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:11:"member_gold";s:1:"1";}' as meta_value
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
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:15:"member_platinum";s:1:"1";}' as meta_value
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


	# Assign comment moderator permissions.
	# Sets all comment moderator users to "comment moderator" by default; next section can selectively promote individual authors
	# parameter: line 3591 and 3592 contain the users and make sure they have the roles we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:17:"comment_moderator";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND u.uid IN ( 8338,8358,8370,8372,8380,8381,8924,65623,65631 )
			AND role.name IN ('comment moderator') AND u.status != 0
		)
	;


	# Assign staff roles to staff member users
	# line 3607 contains the post id for the staff page
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:5:"staff";s:1:"1";}' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_rel_feature f USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a ON a.nid = f.field_rel_feature_nid
			INNER JOIN `minnpost.drupal`.users u ON a.field_author_user_uid = u.uid
			WHERE f.field_rel_feature_nid IS NOT NULL AND n.nid = 68105
	;


	# Assign contributor permissions.
	# Sets all author twos to "contributor" by default; next section can selectively promote individual authors
	# parameter: line 3623 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:11:"contributor";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('author two') AND u.status != 0
		)
	;


	# Assign author permissions.
	# Sets all authors to "author" by default; next section can selectively promote individual authors
	# parameter: line 3640 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"author";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('author') AND u.status != 0
		)
	;


	# Assign editor permissions.
	# Sets all editors and administrators to "editor" by default
	# parameter: line 3657 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"editor";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('editor', 'administrator') AND u.status != 0
		)
	;


	# Assign "business" permissions. This is for business staff.
	# Sets all "user admin" users to "business" by default
	# parameter: line 3674 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:8:"business";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('user admin') AND u.status != 0
		)
	;


	# Assign administrator permissions
	# Set all Drupal super admins to "administrator"
	# parameter: line 3691 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:13:"administrator";s:1:"1";}' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name = 'super admin' AND u.status != 0
		)
	;


	# Assign visual editor setting by default
	# parameter: line 4005 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'rich_editing' as meta_key, 'true' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('super admin', 'user admin', 'author', 'author two', 'editor', 'administrator') AND u.status != 0
		)
	;


	# Assign dismissed stuff by default
	# parameter: line 4005 contains the Drupal permission roles that we want to migrate
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT
			u.uid as user_id, 'dismissed_wp_pointers' as meta_key, 'wp496_privacy' as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.users_roles r USING (uid)
		INNER JOIN `minnpost.drupal`.role role ON r.rid = role.rid
		WHERE (1
			# Uncomment and enter any email addresses you want to exclude below.
			# AND u.mail NOT IN ('test@example.com')
			AND role.name IN ('super admin', 'user admin', 'comment moderator', 'author', 'author two', 'editor', 'administrator') AND u.status != 0
		)
	;


	# reset the merge value so it can start over with fixing the user roles
	UPDATE `minnpost.wordpress`.wp_options
		SET option_value = 1
		WHERE option_name = 'merge_serialized_fields_last_row_checked'
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


	# update comment author name to display name as long as it doesn't have an @ in it because it could be an email address
	UPDATE `minnpost.wordpress`.wp_comments c
		SET comment_author = (
			SELECT display_name
			FROM `minnpost.wordpress`.wp_users u
			WHERE c.user_id = u.ID AND u.display_name NOT LIKE '%@%' AND c.comment_author != u.display_name
		)
	;


	# insert user street/city/state/zip/country
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_street_address' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 16 and pv2.value != ''
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_city' as meta_key, pv.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv ON u.uid = pv.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf ON pv.fid = pf.fid
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf.fid = 6
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_state' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 7
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_zip_code' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 14
	;
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_country' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 13
	;


	# bunch of donation/membership status fields on the user

	# stripe customer id
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_stripe_customer_id' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 20
	;

	# annual recurring amount
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_annual_recurring_amount' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 19
	;

	# coming year contributions
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_coming_year_contributions' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 18
	;

	# prior year contributions
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_prior_year_contributions' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 17
	;

	# active sustainer
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_sustaining_member' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 9
	;

	# next partner claim date
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_next_partner_claim_date' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 22
	;

	# exclude from current campaign
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_exclude_from_current_campaign' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 21
	;

	# user's reading topics
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT DISTINCT u.uid as user_id, '_reading_topics' as meta_key, pv2.`value` as meta_value
		FROM `minnpost.drupal`.users u
		INNER JOIN `minnpost.drupal`.profile_values pv2 ON u.uid = pv2.uid 
		INNER JOIN `minnpost.drupal`.profile_fields pf2 ON pv2.fid = pf2.fid
		WHERE pf2.fid = 10 AND pv2.value != ''
	;

	UPDATE `minnpost.wordpress`.wp_usermeta SET meta_value = '' WHERE meta_value = '0'; # stupid thing from drupal


	# last timestamp when user claimed a partner offer
	INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
		SELECT
			field_user_uid as user_id,
			'_last_partner_claim_date' as meta_key,
			FROM_UNIXTIME(field_claimed_value, "%M %e, %Y") as meta_value
			FROM `minnpost.drupal`.content_type_partner_offer_instance main
			WHERE field_claimed_value = (
				SELECT MAX(field_claimed_value)
					FROM `minnpost.drupal`.content_type_partner_offer_instance
					WHERE field_user_uid = main.field_user_uid
				)
			ORDER BY field_user_uid
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
	# this may not be necessary
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
	# this may not be necessary
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


	# Assign staff member value to author
	# this one does take the vid into account
	# line 4072 contains the post id for the staff page
	INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta (post_id, meta_key, meta_value)
		SELECT DISTINCT
			a.nid as post_id, '_staff_member' as meta_key, 'on' as meta_value
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_rel_feature f USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_type_author a ON a.nid = f.field_rel_feature_nid
			WHERE f.field_rel_feature_nid IS NOT NULL AND n.nid = 68105
	;



# Section 11 - Zones and redirect items. The order doesn't matter here.

	# Redirects for the Redirection plugin - https://wordpress.org/plugins/redirection/
	# these are from the path_redirect table
	# use line 4107 to exclude things if we find out they break when used in wordpress
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
			WHERE p.redirect NOT IN ('about-us')
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


	# redirects for spill urls
	INSERT INTO `wp_redirection_items` (`url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
		VALUES(
			'/more-in-politics-policy',
			0,
			0,
			1,
			CURRENT_TIMESTAMP(),
			1,
			'enabled',
			'url',
			301,
			CONCAT(
				(
				SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				),
				'/',
				'politics-policy'
			),
			'url',
			''
		)
	;


	# redirects for rss feeds
	# doing these manually because no one really uses them anyway
	INSERT INTO `wp_redirection_items` (`url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
		VALUES
			(
				'/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'feed'
				),
				'url',
				''
			),
			(	'/section/166/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'politics-policy/feed'
				),
				'url',
				''
			),
			(	'/section/167/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'health/feed'
				),
				'url',
				''
			),
			(	'/section/168/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'education/feed'
				),
				'url',
				''
			),
			(	'/section/169/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'environment/feed'
				),
				'url',
				''
			),
			(	'/section/113/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'arts-culture/feed'
				),
				'url',
				''
			),
			(	'/section/170/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'business/feed'
				),
				'url',
				''
			),
			(	'/section/171/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'sports/feed'
				),
				'url',
				''
			),
			(	'/section/233/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'perspectives/feed'
				),
				'url',
				''
			),
			(	'/department/30915/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'artscape/feed'
				),
				'url',
				''
			),
			(	'/department/30885/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'community-sketchbook/feed'
				),
				'url',
				''
			),
			(	'/department/30805/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'community-voices/feed'
				),
				'url',
				''
			),
			(	'/department/30908/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'earth-journal/feed'
				),
				'url',
				''
			),
			(	'/department/30833/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'eric-black-ink/feed'
				),
				'url',
				''
			),
			(	'/department/30795/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'glean/feed'
				),
				'url',
				''
			),
			(	'/department/30871/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'inside-minnpost/feed'
				),
				'url',
				''
			),
			(	'/department/30912/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'macro-micro-minnesota/feed'
				),
				'url',
				''
			),
		
			(	'/department/30870/rss.xml',
				'0',
				'0',
				1,
				CURRENT_TIMESTAMP(),
				1,
				'enabled',
				'url',
				301,
				CONCAT(
					(
					SELECT option_value
					FROM `minnpost.wordpress`.wp_options
					WHERE option_name = 'siteurl'
					),
					'/',
					'second-opinion/feed'
				),
				'url',
				''
			)
	;


	# redirects for user profile urls
	# we may not put this into a menu, but we can still maintain the urls
	INSERT INTO `minnpost.wordpress`.wp_redirection_items
		(`url`, `regex`, `position`, `last_count`, `last_access`, `group_id`, `status`, `action_type`, `action_code`, `action_data`, `match_type`, `title`)
		SELECT DISTINCT
			CONCAT(
				'/users/',
				REPLACE(REPLACE(TRIM(LOWER(u.name)), ' ', '-'), '---', '-')
			) `url`,
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
				'/users/',
				u2.ID) `action_data`,
			'url' `match_type`,
			'' `title`
			FROM `minnpost.drupal`.users u
			INNER JOIN `minnpost.wordpress`.wp_users u2 ON u.uid = u2.ID
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


	# fix broken page hierarchies
	UPDATE wp_posts p
		SET post_parent = (
			SELECT nid
			FROM `minnpost.drupal`.node n
			WHERE n.title = 'MinnPost Advertising Information' AND n.type = 'page'
		)
		WHERE p.post_title = 'Politics Advertising Policy'
	;



# Section 12 - User Account pages. We need to run this after all the other posts have been added, but before the menus

	# we need to add user pages so the menu can realize they are actual pages
	# the plugin will skip adding these if they already exist

	# User account page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_type, `post_status`)
		VALUES (1, CURRENT_TIMESTAMP(), '[account-info]', 'Your MinnPost account', '', 'user', '', '', CURRENT_TIMESTAMP(), '', 'page', 'publish')
	;


	# User login page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-login-form]',
			'Log in to MinnPost',
			'',
			'login',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# User register page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-register-form]',
			'Create your MinnPost account',
			'',
			'register',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# lost password page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-password-lost-form]',
			'Forgot Your Password?',
			'',
			'password-lost',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# reset password page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-password-reset-form]',
			'Set a New Password',
			'',
			'password-reset',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# change password page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-password-change-form]',
			'Change Your Password',
			'',
			'password',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# account settings page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-account-settings-form]',
			'Account Settings',
			'',
			'account-settings',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;


	# preferences page
	INSERT INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_content_filtered, post_parent, post_type, `post_status`)
		VALUES (
			1,
			CURRENT_TIMESTAMP(),
			'[custom-account-preferences-form]',
			'Website & Communication Preferences',
			'',
			'preferences',
			'',
			'',
			CURRENT_TIMESTAMP(),
			'',
			(SELECT ID FROM wp_posts p2 WHERE p2.post_name = 'user'),
			'page',
			'publish'
		)
	;



# Section 13 - Menus. We can't run this one all at once because we have to wait for cron to finish before deleting. The order doesn't matter though.


	# Temporary table for menus
	CREATE TABLE `wp_menu` (
		`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`name` varchar(200) NOT NULL DEFAULT '',
		`title` varchar(200) NOT NULL DEFAULT '',
		`placement` varchar(200) NOT NULL DEFAULT '',
		PRIMARY KEY (`id`)
	);


	# Temporary table for menu items
	CREATE TABLE `wp_menu_items` (
		`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		`menu-name` varchar(200) NOT NULL DEFAULT '',
		`menu-item-title` varchar(200) NOT NULL DEFAULT '',
		`menu-item-url` varchar(200) NOT NULL DEFAULT '',
		`menu-item-parent` varchar(200) DEFAULT '',
		`menu-item-parent-id` bigint(20) unsigned DEFAULT NULL,
		`menu-item-status` varchar(200) NOT NULL DEFAULT 'publish',
		`menu-item-access` varchar(200) DEFAULT NULL,
		PRIMARY KEY (`id`)
	);


	# add menus
	# parameter: line 4887 contains the menu types in drupal that we don't want to migrate
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


	# add a menu for user account access links
	INSERT INTO `minnpost.wordpress`.wp_menu
		(name, title, placement)
		VALUES('menu-user-account-access', 'User Account Access', 'user_account_access')
	;


	# add a menu for user account management links
	INSERT INTO `minnpost.wordpress`.wp_menu
		(name, title, placement)
		VALUES('menu-user-account-management', 'User Account Management', 'user_account_management');
	;


	# add menu items
	# parameter: line 4946 important parameter to keep out/force some urls because of how they're stored in drupal
	INSERT INTO `minnpost.wordpress`.wp_menu_items
		(`menu-name`, `menu-item-title`, `menu-item-url`, `menu-item-parent`)
		SELECT DISTINCT
			m.menu_name `menu-name`,
			l.link_title `menu-item-title`,
			REPLACE(REPLACE(IFNULL(a.dst, l.link_path), '<front>', '/'), 'https://www.minnpost.com/', CONCAT((
			SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				), '/')) `menu-item-url`,
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


	# insert user account access links
	INSERT INTO `minnpost.wordpress`.wp_menu_items
		(`menu-name`, `menu-item-title`, `menu-item-url`, `menu-item-parent`, `menu-item-access`)
		VALUES
			('menu-user-account-access', 'Log in', 'user/login', NULL, 'out'),
			('menu-user-account-access', 'Create Account', 'user/register', NULL, 'out'),
			('menu-user-account-access', 'Welcome', 'user', NULL, 'in'),
			('menu-user-account-access', 'Your Account', 'user', 'Welcome', 'in'),
			('menu-user-account-access', 'Account Settings', 'user/account-settings', 'Welcome', 'in'),
			('menu-user-account-access', 'Log out', 'wp_logout_url()', 'Welcome', 'in')
	;


	# insert user account management links
	INSERT INTO `minnpost.wordpress`.wp_menu_items
		(`menu-name`, `menu-item-title`, `menu-item-url`, `menu-item-parent`, `menu-item-access`)
		VALUES
			('menu-user-account-management', 'Your MinnPost', 'user', NULL, 'in'),
			('menu-user-account-management', 'Preferences', 'user/preferences', NULL, 'in'),
			('menu-user-account-management', 'Public Profile', 'users/userid', NULL, 'in'),
			('menu-user-account-management', 'Account Settings', 'user/account-settings', NULL, 'in'),
			('menu-user-account-management', 'Change Password', 'user/password', NULL, 'in')
	;


	# get rid of those temporary menu tables
	# can't run this until after the migrate-random-things.php task runs twice. once to add parent items, once to add their children if applicable
	DROP TABLE wp_menu;
	DROP TABLE wp_menu_items;



# Section 14 - widgets and ads and sidebar such stuff. This depends on cron. The order has to be after posts since that table gets updated. We can skip this section if we're testing other stuff or if we didn't clear all of the relevant items.

	# replace content when necessary


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
				WHERE module = 'minnpost_ads' AND theme = 'siteskin' AND name != 'minnpost_newsletter_sunday_review' AND delta != 'TopLeft' AND name != 'advertising-weather'
				ORDER BY weight DESC, delta
	;


	# we have to add a Middle tag manually with is_single conditional
	INSERT IGNORE INTO `minnpost.wordpress`.ads
		(tag, tag_id, tag_name, priority, conditions)
		VALUES('Middle', 'Middle', 'Middle', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}')
	;

	# we have to add the x100 - x110 tags manually with is_single conditional
	INSERT IGNORE INTO `minnpost.wordpress`.ads
		(tag, tag_id, tag_name, priority, conditions)
		VALUES
			('x100', 'x100', 'x100', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x101', 'x101', 'x101', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x102', 'x102', 'x102', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x103', 'x103', 'x103', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x104', 'x104', 'x104', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x105', 'x105', 'x105', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x106', 'x106', 'x106', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x107', 'x107', 'x107', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x108', 'x108', 'x108', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x109', 'x109', 'x109', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}'),
			('x110', 'x110', 'x110', 10, 'a:1:{s:4:"node";a:2:{s:6:"values";a:1:{s:7:"article";s:7:"article";}s:7:"options";a:1:{s:9:"node_form";s:1:"1";}}}')
	;

	# we have to add a Middle3 tag manually with is_home conditional
	INSERT IGNORE INTO `minnpost.wordpress`.ads
		(tag, tag_id, tag_name, priority, conditions)
		VALUES('Middle3', 'Middle3', 'Middle3', 10, 'a:1:{s:4:"path";a:1:{s:6:"values";a:1:{s:7:"<front>";s:7:"<front>";}}}')
	;


	# have to wait for migrate cron to run before deleting the table


	# get rid of the temporary ad table
	DROP TABLE ads;


	# temporary table for basic html sidebar items and their placement
	CREATE TABLE `wp_sidebars` (
		`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
		`title` varchar(255) NOT NULL DEFAULT '',
		`url` varchar(255) DEFAULT NULL,
		`content` text NOT NULL,
		`type` varchar(255) NOT NULL DEFAULT 'custom_html',
		`show_on` varchar(255) DEFAULT '',
		`categories` varchar(255) DEFAULT NULL,
  		`tags` varchar(255) DEFAULT NULL,
  		`batch` int(11) DEFAULT NULL,
		PRIMARY KEY (`id`)
	); # i think we don't need the collation stuff anymore


	# put the active sidebar items into that temporary table
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, content, show_on, batch)
		SELECT
            IFNULL(d.field_display_title_value, CONCAT('!', n.title)) as title,
            IF(LENGTH(u.field_url_url)>0, CONCAT(CONCAT(IF(LENGTH(f.filepath)>0, CONCAT('<div class="image">',IFNULL(CONCAT('<a href="/', u.field_url_url, '">'), ''), '<img src="https://www.minnpost.com/', f.filepath, '">', IF(LENGTH(u.field_url_url) > 0, '</a></div>', '</div>')),''), IF(LENGTH(nr.body)>0, nr.body, field_teaser_value)), '<p><a href="/', u.field_url_url, '" class="a-more">More</a></p>'), CONCAT(IF(LENGTH(f.filepath)>0, CONCAT('<div class="image">',IFNULL(CONCAT('<a href="/', u.field_url_url, '">'), ''), '<img src="https://www.minnpost.com/', f.filepath, '">', IF(LENGTH(u.field_url_url) > 0, '</a></div>', '</div>')),''), IF(LENGTH(nr.body)>0, nr.body, REPLACE(field_teaser_value, '[newsletter_embed:dc]', '[newsletter_embed newsletter="dc"]')))) as content,
            IFNULL(i.action_data, GROUP_CONCAT(field_visibility_value)) as show_on,
            '4' as batch
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


	# fix the table
	#ALTER TABLE `minnpost.wordpress`.wp_sidebars CONVERT TO CHARACTER SET utf8mb4 collate utf8mb4_unicode_ci;


	# update urls
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET show_on = REPLACE(show_on, CONCAT((
			SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				), '/'),
			'')
	;


	# update content urls and link attributes
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET content = REPLACE(content, ' target="_self"', '')
	;
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET content = REPLACE(content, ' target="_blank"', '')
	;
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET content = REPLACE(content, '<a href="https://www.minnpost.com/', CONCAT('<a href="', (
			SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				), '/'))
	;
	UPDATE `minnpost.wordpress`.wp_sidebars s
		SET content = REPLACE(content, '<a href="http://www.minnpost.com/', CONCAT('<a href="', (
			SELECT option_value
				FROM `minnpost.wordpress`.wp_options
				WHERE option_name = 'siteurl'
				), '/'))
	;


	# Fix image urls in widget content
	# in our case, we use this to make the urls absolute, at least for now
	UPDATE `minnpost.wordpress`.wp_sidebars
	SET content = REPLACE(content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
	;

	
	# manually add a few sidebars
	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`, `batch`)
		VALUES
			('The Glean', 'glean', '', 'minnpostspills_widget', '<front>', 'glean', NULL, 1)
	;

	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`, `batch`)
		VALUES
			('Featured Columns', NULL, 'menu-featured-columns', 'nav_menu', '<front>', NULL, NULL, 2)
	;

	
	# add the active minnpost spills widgets into temporary table
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, url, content, type, show_on, categories, tags, batch)
		SELECT
			n.title as title,
			u.field_url_url as url,
			nr.body as content,
			'minnpostspills_widget' as type,
			GROUP_CONCAT(DISTINCT field_visibility_value) as show_on,
			GROUP_CONCAT(DISTINCT IFNULL(a.dst, d.title)) as categories,
			GROUP_CONCAT(DISTINCT t.name) as tags,
			'3' as batch
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


	# manually add a few more sidebars
	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`, `batch`)
		VALUES
			('Recent Stories', NULL, '', 'rpwe_widget', '!<front>', NULL, NULL, 5)
	;

	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`, `batch`)
		VALUES
			('', NULL, '', 'popular-widget', '*', NULL, NULL, 6)
	;


	INSERT INTO `wp_sidebars` (`title`, `url`, `content`, `type`, `show_on`, `categories`, `tags`, `batch`)
		VALUES
			('Thanks to our major sponsors', NULL, '[mp_sponsors columns="1" image="yes" title="no" link="yes" orderby="post_date" order="DESC"]', 'custom_html', 'footer', NULL, NULL, 7)
	;


	# add some basic blocks from drupal as widgets
	INSERT INTO `minnpost.wordpress`.wp_sidebars
		(title, url, content, type, show_on, categories, tags, batch)
		SELECT REPLACE(REPLACE(CONCAT('!', info), '!hp_staff', 'MinnPost Staff'), '!hp_donors', 'Thanks to our generous donors') as title, null as url, body as content, 'custom_html' as type, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(delta, 1, 'footer'), 2, 'newsletter-footer'), 3, 'newsletter'), 5, 'newsletter'), 'menu-footer-primary', 'newsletter') as show_on, null as categories, null as tags, 7 as batch
			FROM `minnpost.drupal`.blocks
			INNER JOIN `minnpost.drupal`.boxes USING(bid)
			WHERE body NOT LIKE '%gorton%' AND body NOT LIKE '%phase2%' AND delta NOT IN ('admin', 'features', 'menu-footer-secondary', '0')
			ORDER BY delta
	;

	# Prevent easy lazy load images for newsletters
	UPDATE `minnpost.wordpress`.wp_sidebars
		SET content = REPLACE(content, '<img src="', '<img class="no-lazy" src="')
		WHERE show_on = 'newsletter' OR show_on = 'newsletter-footer'
	;


	# add the migrated field
	ALTER TABLE `minnpost.wordpress`.wp_sidebars ADD migrated TINYINT(1) DEFAULT 0;


	# after the plugin runs, delete the temporary sidebar table
	DROP TABLE wp_sidebars;


	# use widgets for news by region - 1: from greater minnesota, 2: metro area, 3: world/nation, 4: washington bureau
	# these numbers change if we have to recreate the widgets. ugh.
	UPDATE `minnpost.wordpress`.wp_posts
		SET post_content = '<!--break-->
	[widget_instance id="minnpostspills_widget-8"]

	[widget_instance id="minnpostspills_widget-21"]

	[widget_instance id="minnpostspills_widget-11"]

	[widget_instance id="minnpostspills_widget-22"]'
		WHERE ID = 30750;
	;



# Section 15 - manually create/edit any posts/pages that we need. The order doesn't matter but it has to be after section 8.

	# Subscribe DC Memo page
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(post_author, post_date, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_type, `post_status`)
		VALUES (1, CURRENT_TIMESTAMP(), '[newsletter_embed newsletter="full-dc"]By subscribing, you are agreeing to MinnPost\'s <a href="https://www.minnpost.com/terms-of-use">Terms of Use</a>. MinnPost promises not to share your information without your consent. For more information, please see our <a href="privacy">privacy policy</a>.', 'Subscribe to D.C. Memo', '', 'subscribe-dc-memo', '', '', CURRENT_TIMESTAMP(), 'page', 'publish')
	;


	# Remove title from DC Memo subscribe page display
	INSERT INTO `minnpost.wordpress`.wp_postmeta
		(`post_id`, `meta_key`, `meta_value`)
		SELECT
			p.ID `post_id`,
			'_mp_remove_title_from_display' `meta_key`,
			'on' `meta_value`
			FROM `minnpost.wordpress`.wp_posts p
			WHERE p.post_title = 'Subscribe to D.C. Memo'
	;



	# Submit a letter to the editor page
	INSERT IGNORE INTO `minnpost.wordpress`.wp_posts
		(id, post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt,
		post_name, to_ping, pinged, post_modified, post_modified_gmt, post_type, `post_status`)
		SELECT DISTINCT
			n.nid `id`,
			n.uid `post_author`,
			FROM_UNIXTIME(n.created) `post_date`,
			CONVERT_TZ(FROM_UNIXTIME(n.created), 'America/Chicago', 'UTC') `post_date_gmt`,
			CONCAT(r.body, '[gravityform id="1" title="false" description="false"]') `post_content`,
			n.title `post_title`,
			t.field_teaser_value `post_excerpt`,
			substring_index(a.dst, '/', -1) `post_name`,
			'',
			'',
			FROM_UNIXTIME(n.changed) `post_modified`,
			CONVERT_TZ(FROM_UNIXTIME(n.changed), 'America/Chicago', 'UTC') `post_modified_gmt`,
			'page' `post_type`,
			IF(n.status = 1, 'publish', 'draft') `post_status`
		FROM `minnpost.drupal`.node n
		LEFT OUTER JOIN `minnpost.drupal`.node_revisions r
			USING(nid, vid)
		LEFT OUTER JOIN `minnpost.drupal`.url_alias a
			ON a.src = CONCAT('node/', n.nid)
		LEFT OUTER JOIN `minnpost.drupal`.content_field_teaser t USING(nid, vid)
		WHERE n.nid = 81046
	;


	# Fix image/file urls in letter to editor content
	# in our case, we use this to make the urls absolute, at least for now
	# no need for vid stuff
	UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
	WHERE ID = 81046
	;


	# fix the category that links to "submit a letter" because its url is broken
	UPDATE `minnpost.wordpress`.wp_termmeta
		SET meta_value = '<p>MinnPost welcomes original letters from readers on current topics of general interest. Interested in joining the conversation? <strong><a href="/submit-letter">Submit your letter to the editor.&nbsp;</a></strong></p><p>The choice of letters for publication is at the discretion of MinnPost editors; they will not be able to respond to individual inquiries about letters.</p>'
		WHERE meta_key = '_mp_category_body' AND term_id = 19054
	;



# Section 16 - General WordPress settings.

	
# Section 17 - Things that have to be manually imported

	# popup-settings.csv (import into database table wp_postmeta, use replace rather than insert)
	# popup-themes.xml (import into core WordPress Importer)
	# object-sync-for-salesforce-data-export.json
