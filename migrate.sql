# DRUPAL-TO-WORDPRESS CONVERSION SCRIPT

# Changelog

# 07.29.2010 - Updated by Scott Anderson / Room 34 Creative Services http://blog.room34.com/archives/4530
# 02.06.2009 - Updated by Mike Smullin http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/
# 05.15.2007 - Updated by D’Arcy Norman http://www.darcynorman.net/2007/05/15/how-to-migrate-from-drupal-5-to-wordpress-2/
# 05.19.2006 - Created by Dave Dash http://spindrop.us/2006/05/19/migrating-from-drupal-47-to-wordpress/

# This assumes that WordPress and Drupal are in separate databases, named 'wordpress' and 'drupal'.
# If your database names differ, adjust these accordingly.

# Empty previous content from WordPress database.
TRUNCATE TABLE `minnpost.wordpress`.wp_comments;
TRUNCATE TABLE `minnpost.wordpress`.wp_links;
TRUNCATE TABLE `minnpost.wordpress`.wp_postmeta;
TRUNCATE TABLE `minnpost.wordpress`.wp_posts;
TRUNCATE TABLE `minnpost.wordpress`.wp_term_relationships;
TRUNCATE TABLE `minnpost.wordpress`.wp_term_taxonomy;
TRUNCATE TABLE `minnpost.wordpress`.wp_terms;

# If you're not bringing over multiple Drupal authors, comment out these lines and the other
# author-related queries near the bottom of the script.
# This assumes you're keeping the default admin user (user_id = 1) created during installation.
DELETE FROM `minnpost.wordpress`.wp_users WHERE ID > 1;
DELETE FROM `minnpost.wordpress`.wp_usermeta WHERE user_id > 1;


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
	FROM `minnpost.092515`.term_data d
	INNER JOIN `minnpost.092515`.term_hierarchy h
		USING(tid)
	INNER JOIN `minnpost.092515`.term_node n
		USING(tid)
	LEFT OUTER JOIN `minnpost.092515`.url_alias a
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
	FROM `minnpost.092515`.term_data d
	INNER JOIN `minnpost.092515`.term_hierarchy h
		USING(tid)
	INNER JOIN `minnpost.092515`.term_node n
		USING(tid)
	WHERE (1
	 	# This helps eliminate spam tags from import; uncomment if necessary.
	 	# AND LENGTH(d.name) < 50
	)
;


# Posts from Drupal stories
# Keeps private posts hidden.
# line 99 contains the Drupal content types that we want to migrate
INSERT INTO `minnpost.wordpress`.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_modified, post_type, `post_status`)
	SELECT DISTINCT
		n.nid `id`,
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		r.body `post_content`,
		n.title `post_title`,
		r.teaser `post_excerpt`,
		substring_index(a.dst, '/', -1) `post_name`,
		FROM_UNIXTIME(n.changed) `post_modified`,
		n.type `post_type`,
		IF(n.status = 1, 'publish', 'draft') `post_status`
	FROM `minnpost.092515`.node n
	INNER JOIN `minnpost.092515`.node_revisions r
		USING(vid)
	LEFT OUTER JOIN `minnpost.092515`.url_alias a
		ON a.src = CONCAT('node/', n.nid)
	# Add more Drupal content types below if applicable.
	WHERE n.type IN ('article', 'article_full', 'audio', 'page', 'video')
;


# Fix post type; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-17826
# Add more Drupal content types below if applicable. Must match all types from line 99 that should be imported as 'posts'
UPDATE `minnpost.wordpress`.wp_posts
	SET post_type = 'post'
	WHERE post_type IN ('article', 'article_full', 'audio', 'video')
;


## Get Raw HTML content from article_full posts
# requires the Raw HTML plugin in WP to be enabled
# wrap it in [raw][/raw]


# create temporary table for raw html content
# Temporary table for department terms
CREATE TABLE `wp_posts_raw` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_content_raw` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`ID`)
);


# store raw values in temp table
INSERT INTO `minnpost.wordpress`.wp_posts_raw
	(id, post_content_raw)
	SELECT a.nid, field_html_value
	FROM `minnpost.092515`.content_type_article_full a
	INNER JOIN `minnpost.092515`.node AS n ON a.vid = n.vid
	WHERE field_html_value IS NOT NULL
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
INSERT INTO `minnpost.wordpress`.wp_posts_audio
	(id, post_content_audio)
	SELECT a.nid, CONCAT('https://www.minnpost.com/', f.filepath) `post_content_audio`
		FROM `minnpost.092515`.content_type_audio a
		INNER JOIN `minnpost.092515`.node AS n ON a.vid = n.vid
		INNER JOIN `minnpost.092515`.files AS f ON a.field_audio_file_fid = f.fid
;


# append audio file to the post body
UPDATE `minnpost.wordpress`.wp_posts
	JOIN `minnpost.wordpress`.wp_posts_audio
	ON wp_posts.ID = wp_posts_audio.ID
	SET wp_posts.post_content = CONCAT(wp_posts.post_content, '<p>[audio mp3="', wp_posts_audio.post_content_audio, '"]</p>')
;


# get rid of that temporary audio table
DROP TABLE wp_posts_audio;


# add audio format for audio posts
INSERT INTO `minnpost.wordpress`.wp_terms (name, slug) VALUES ('post-format-audio', 'post-format-audio');


# add format to taxonomy
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id `term_id`, 'post_format' `taxonomy`
		FROM wp_terms
		WHERE `minnpost.wordpress`.wp_terms.name = 'post-format-audio'
;


# use audio format for audio posts
INSERT INTO wp_term_relationships (object_id, term_taxonomy_id)
	SELECT n.nid, tax.term_taxonomy_id
		FROM `minnpost.092515`.node n
		CROSS JOIN `minnpost.wordpress`.wp_term_taxonomy tax
		LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
		WHERE `minnpost.092515`.n.type = 'audio' AND tax.taxonomy = 'post_format' AND t.name = 'post-format-audio'
;


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
INSERT INTO `minnpost.wordpress`.wp_posts_video
	(id, post_content_video)
	SELECT v.nid, REPLACE(CONCAT('[video src="https://www.minnpost.com/', f.filepath, '"]'), '.flv', '.mp4') `post_content_video`
		FROM `minnpost.092515`.content_type_video v
		INNER JOIN `minnpost.092515`.node AS n ON v.vid = n.vid
		INNER JOIN `minnpost.092515`.files AS f ON v.field_flash_file_fid = f.fid
;

# store video urls for embed videos in temp table
# drupal 6 (at least our version) only does vimeo and youtube

# vimeo
INSERT INTO `minnpost.wordpress`.wp_posts_video
	(id, post_content_video)
	SELECT v.nid, CONCAT('[embed]https://vimeo.com/', v.field_embedded_video_value, '[/embed]') `post_content_video`
		FROM `minnpost.092515`.content_field_embedded_video v
		WHERE v.field_embedded_video_provider = 'vimeo'
		GROUP BY v.nid
;

# youtube
INSERT INTO `minnpost.wordpress`.wp_posts_video
	(id, post_content_video)
	SELECT v.nid, CONCAT('[embed]https://www.youtube.com/watch?v=', v.field_embedded_video_value, '[/embed]') `post_content_video`
		FROM `minnpost.092515`.content_field_embedded_video v
		WHERE v.field_embedded_video_provider = 'youtube'
		GROUP BY v.nid
;


# append video file or embed content to the post body
UPDATE `minnpost.wordpress`.wp_posts
	JOIN `minnpost.wordpress`.wp_posts_video
	ON wp_posts.ID = wp_posts_video.ID
	SET wp_posts.post_content = CONCAT(wp_posts.post_content, '<p>', wp_posts_video.post_content_video, '</p>')
;


# get rid of that temporary video table
DROP TABLE wp_posts_video;


# add video format for video posts
INSERT INTO `minnpost.wordpress`.wp_terms (name, slug) VALUES ('post-format-video', 'post-format-video');


# add format to taxonomy
INSERT INTO `minnpost.wordpress`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id `term_id`, 'post_format' `taxonomy`
		FROM wp_terms
		WHERE `minnpost.wordpress`.wp_terms.name = 'post-format-video'
;


# use video format for video posts
INSERT INTO wp_term_relationships (object_id, term_taxonomy_id)
	SELECT n.nid, tax.term_taxonomy_id
		FROM `minnpost.092515`.node n
		CROSS JOIN `minnpost.wordpress`.wp_term_taxonomy tax
		LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
		WHERE `minnpost.092515`.n.type = 'video' AND tax.taxonomy = 'post_format' AND t.name = 'post-format-video'
;


# Set all pages to "pending".
# If you're keeping the same page structure from Drupal, comment out this query
# and the new page INSERT at the end of this script.
# UPDATE `minnpost.wordpress`.wp_posts SET post_status = 'pending' WHERE post_type = 'page';

# Post/Tag relationships
INSERT INTO `minnpost.wordpress`.wp_term_relationships (object_id, term_taxonomy_id)
	SELECT DISTINCT nid, tid FROM `minnpost.092515`.term_node
;


# Update tag counts.
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# Comments
# Keeps unapproved comments hidden.
# Incorporates change noted here: http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-32169
INSERT INTO `minnpost.wordpress`.wp_comments
	(comment_ID, comment_post_ID, comment_date, comment_content, comment_parent, comment_author,
	comment_author_email, comment_author_url, comment_approved, user_id)
	SELECT DISTINCT
		cid, nid, FROM_UNIXTIME(timestamp), comment, thread, name,
		mail, homepage, status, uid
		FROM `minnpost.092515`.comments
;


# Update comments count on wp_posts table.
UPDATE `minnpost.wordpress`.wp_posts
	SET `comment_count` = (
		SELECT COUNT(`comment_post_id`)
		FROM `minnpost.wordpress`.wp_comments
		WHERE `minnpost.wordpress`.wp_posts.`id` = `minnpost.wordpress`.wp_comments.`comment_post_id`
	)
;


# Fix images in post content; uncomment if you're moving files from "files" to "wp-content/uploads".
# in our case, we use this to make the urls absolute, at least for now
#UPDATE `minnpost.wordpress`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"/wp-content/uploads/');
UPDATE `minnpost.wordpress`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
;


# Fix taxonomy; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-27140
UPDATE IGNORE `minnpost.wordpress`.wp_term_relationships, `minnpost.wordpress`.wp_term_taxonomy
	SET `minnpost.wordpress`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress`.wp_term_taxonomy.term_taxonomy_id
	WHERE `minnpost.wordpress`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress`.wp_term_taxonomy.term_id
;


# OPTIONAL ADDITIONS -- REMOVE ALL BELOW IF NOT APPLICABLE TO YOUR CONFIGURATION

# CATEGORIES
# These are NEW categories, not in `minnpost.092515`. Add as many sets as needed.
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
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_dept (term_id, name, slug)
	SELECT nid `term_id`,
	title `name`,
	substring_index(a.dst, '/', -1) `slug`
	FROM `minnpost.092515`.node n
	LEFT OUTER JOIN `minnpost.092515`.url_alias a ON a.src = CONCAT('node/', n.nid)
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


# Create relationships for each story to the deparments it had in Drupal
# Track this relationship by the term_id_old field
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT dept.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id from wp_term_taxonomy tax
	INNER JOIN wp_terms term ON tax.term_id = term.term_id
	INNER JOIN `minnpost.092515`.content_field_department dept ON term.term_id_old = dept.field_department_nid
	WHERE tax.taxonomy = 'category'
;


# Empty term_id_old values so we can start over with our auto increment and still track for sections
UPDATE `minnpost.wordpress`.wp_terms SET term_id_old = NULL;


# get rid of that temporary department table
DROP TABLE wp_terms_dept;


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
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_section (term_id, name, slug)
	SELECT nid `term_id`,
	title `name`,
	substring_index(a.dst, '/', -1) `slug`
	FROM `minnpost.092515`.node n
	LEFT OUTER JOIN `minnpost.092515`.url_alias a ON a.src = CONCAT('node/', n.nid)
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
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT section.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id from wp_term_taxonomy tax
	INNER JOIN wp_terms term ON tax.term_id = term.term_id
	INNER JOIN `minnpost.092515`.content_field_section section ON term.term_id_old = section.field_section_nid
	WHERE tax.taxonomy = 'category'
;


# Empty term_id_old values so we can start over with our auto increment if applicable
UPDATE `minnpost.wordpress`.wp_terms SET term_id_old = NULL;


# get rid of that temporary section table
DROP TABLE wp_terms_section;


# get rid of that term_id_old field if we are done migrating into wp_terms
ALTER TABLE wp_terms DROP COLUMN term_id_old;


# Update category counts.
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# Fix taxonomy; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-27140
UPDATE IGNORE `minnpost.wordpress`.wp_term_relationships, `minnpost.wordpress`.wp_term_taxonomy
	SET `minnpost.wordpress`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress`.wp_term_taxonomy.term_taxonomy_id
	WHERE `minnpost.wordpress`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress`.wp_term_taxonomy.term_id
;


# stuff for users:
# If we change the inner join to left join on the insert into wp_users, we can get all users inserted
# however, this will break the roles. we need to have the roles at least created in WordPress before doing this
# and then we will need some joins to do the inserting


# example:
#SELECT DISTINCT u.uid, 'wp_capabilities', 'a:1:{s:6:"author";s:1:"1";}', re.name
#FROM `minnpost.092515`.users u
#INNER JOIN `minnpost.092515`.users_roles r USING (uid)
#INNER JOIN `minnpost.092515`.role re USING (rid)
#WHERE (1
	# Uncomment and enter any email addresses you want to exclude below.
	# AND u.mail NOT IN ('test@example.com')
#)

# SELECT DISTINCT
# 	u.uid, u.mail, NULL, u.name, u.mail,
# 	FROM_UNIXTIME(created), '', 0, u.name
# FROM `minnpost.092515`.users u
# INNER JOIN `minnpost.092515`.users_roles r USING (uid)
# INNER JOIN `minnpost.092515`.role role USING (rid)
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
	FROM `minnpost.092515`.users u
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND u.uid != 0
	)
;


# Assign author permissions.
# Sets all authors to "author" by default; next section can selectively promote individual authors
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:6:"author";s:1:"1";}' as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.users_roles r USING (uid)
	INNER JOIN `minnpost.092515`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('author', 'author two', 'editor', 'user admin', 'administrator')
	)
;
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_user_level' as meta_key, '2' as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.users_roles r USING (uid)
	INNER JOIN `minnpost.092515`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name IN ('author', 'author two', 'editor', 'user admin', 'administrator')
	)
;


# Assign administrator permissions
# Set all Drupal super admins to "administrator"
# todo: do this with an update instead of insert
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_capabilities' as meta_key, 'a:1:{s:13:"administrator";s:1:"1";}' as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.users_roles r USING (uid)
	INNER JOIN `minnpost.092515`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name = 'super admin'
	)
;
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT
		u.uid as user_id, 'wp_user_level' as meta_key, '10' as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.users_roles r USING (uid)
	INNER JOIN `minnpost.092515`.role role ON r.rid = role.rid
	WHERE (1
		# Uncomment and enter any email addresses you want to exclude below.
		# AND u.mail NOT IN ('test@example.com')
		AND role.name = 'super admin'
	)
;



# save user first and last name, if we have them as users in Drupal
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT u.uid as user_id, 'first_name' as meta_key, pv.`value` as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.profile_values pv ON u.uid = pv.uid 
	INNER JOIN `minnpost.092515`.profile_fields pf ON pv.fid = pf.fid
	INNER JOIN `minnpost.092515`.profile_values pv2 ON u.uid = pv2.uid 
	INNER JOIN `minnpost.092515`.profile_fields pf2 ON pv2.fid = pf2.fid
	WHERE pf.fid = 4
;
INSERT IGNORE INTO `minnpost.wordpress`.wp_usermeta (user_id, meta_key, meta_value)
	SELECT DISTINCT u.uid as user_id, 'last_name' as meta_key, pv2.`value` as meta_value
	FROM `minnpost.092515`.users u
	INNER JOIN `minnpost.092515`.profile_values pv2 ON u.uid = pv2.uid 
	INNER JOIN `minnpost.092515`.profile_fields pf2 ON pv2.fid = pf2.fid
	WHERE pf2.fid = 5
;


# Drupal authors who may or may not be users
# these get inserted as posts with a type of guest-author, for the plugin
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
	FROM `minnpost.092515`.node n
	INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
	LEFT OUTER JOIN `minnpost.092515`.url_alias a ON a.src = CONCAT('node/', n.nid)
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
INSERT IGNORE INTO `minnpost.wordpress`.wp_terms_users (term_id, name, slug)
	SELECT DISTINCT
	nid `term_id`,
	title `name`,
	substring_index(a.dst, '/', -1) `slug`
	FROM `minnpost.092515`.node n
	LEFT OUTER JOIN `minnpost.092515`.url_alias a ON a.src = CONCAT('node/', n.nid)
	WHERE n.type='author'
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
INSERT INTO `minnpost.wordpress`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT ca.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
	FROM `minnpost.092515`.content_field_op_author ca
	LEFT OUTER JOIN `minnpost.wordpress`.wp_terms t ON ca.field_op_author_nid = t.user_node_id_old
	LEFT OUTER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_id)
	WHERE tax.term_taxonomy_id IS NOT NULL
	GROUP BY CONCAT(ca.nid, ca.field_op_author_nid)
;


# use the title as the user's display name
# this might be all the info we have about them
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-display_name' `meta_key`,
		n.title `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
;


# make a slug for user's login
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_login' `meta_key`,
		substring_index(a.dst, '/', -1) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
		LEFT OUTER JOIN `minnpost.092515`.url_alias a ON a.src = CONCAT('node/', n.nid)
;


# update count for authors
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# add the email address for the author if we have one
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_email' `meta_key`,
		REPLACE(link.field_link_multiple_url, 'mailto:', '') `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
		INNER JOIN `minnpost.092515`.content_field_link_multiple link USING (nid)
		WHERE field_link_multiple_title = 'Email the author'
;


# add the author's twitter account if we have it
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-twitter' `meta_key`,
		CONCAT('https://twitter.com/', REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(link.field_link_multiple_url, 'http://www.twitter.com/', ''), 'http://twitter.com/', ''), '@', ''), 'https://twitter.com/', ''), '#%21', ''), '/', '')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
		INNER JOIN `minnpost.092515`.content_field_link_multiple link USING (nid)
		WHERE field_link_multiple_title LIKE '%witter%'
;


# add the author's job title if we have it
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-job-title' `meta_key`,
		author.field_op_author_jobtitle_value `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
		INNER JOIN `minnpost.092515`.users user ON author.field_author_user_uid = user.uid
		WHERE author.field_op_author_jobtitle_value IS NOT NULL
;


# if the author is linked to a user account, link them
INSERT INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-linked_account' `meta_key`,
		user.mail `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
		INNER JOIN `minnpost.092515`.users user ON author.field_author_user_uid = user.uid
;



# Change permissions for admins.
# Add any specific user IDs to IN list to make them administrators.
# User ID values are carried over from `minnpost.092515`.
UPDATE `minnpost.wordpress`.wp_usermeta
	SET meta_value = 'a:1:{s:13:"administrator";s:1:"1";}'
	WHERE user_id IN (1) AND meta_key = 'wp_capabilities'
;
UPDATE `minnpost.wordpress`.wp_usermeta
	SET meta_value = '10'
	WHERE user_id IN (1) AND meta_key = 'wp_user_level'
;


# Reassign post authorship.
# we probably don't need this i think
UPDATE `minnpost.wordpress`.wp_posts
	SET post_author = NULL
	WHERE post_author NOT IN (SELECT DISTINCT ID FROM `minnpost.wordpress`.wp_users)
;


# update count for authors again
UPDATE wp_term_taxonomy tt
	SET `count` = (
		SELECT COUNT(tr.object_id)
		FROM wp_term_relationships tr
		WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
	)
;


# assign authors from author nodes to stories where applicable
# not sure this query is useful at all
# UPDATE `minnpost.wordpress`.wp_posts AS posts INNER JOIN `minnpost.092515`.content_field_op_author AS authors ON posts.ID = authors.nid SET posts.post_author = authors.field_op_author_nid;

# get rid of that user_node_id_old field if we are done migrating into wp_term_relationships
ALTER TABLE wp_terms DROP COLUMN user_node_id_old;


# VIDEO - READ BELOW AND COMMENT OUT IF NOT APPLICABLE TO YOUR SITE
# If your Drupal site uses the content_field_video table to store links to YouTube videos,
# this query will insert the video URLs at the end of all relevant posts.
# WordPress will automatically convert the video URLs to YouTube embed code.
#UPDATE IGNORE `minnpost.wordpress`.wp_posts p, `minnpost.092515`.content_field_video v
#	SET p.post_content = CONCAT_WS('\n',post_content,v.field_video_embed)
#	WHERE p.ID = v.nid
#;

# IMAGES - READ BELOW AND COMMENT OUT IF NOT APPLICABLE TO YOUR SITE
# If your Drupal site uses the content_field_image table to store images associated with posts,
# but not actually referenced in the content of the posts themselves, this query
# will insert the images at the top of the post.
# HTML/CSS NOTE: The code applies a "drupal_image" class to the image and places it inside a <div>
# with the "drupal_image_wrapper" class. Add CSS to your WordPress theme as appropriate to
# handle styling of these elements. The <img> tag as written assumes you'll be copying the
# Drupal "files" directory into the root level of WordPress, NOT placing it inside the
# "wp-content/uploads" directory. It also relies on a properly formatted <base href="" /> tag.
# Make changes as necessary before running this script!

/*UPDATE IGNORE `minnpost.wordpress`.wp_posts p, `minnpost.092515`.content_field_main_image i, `minnpost.092515`.files f
	SET p.post_content =
		CONCAT(
			CONCAT(
				'<div class="drupal_image_wrapper"><img src="https://www.minnpost.com/',
				f.filepath,
				'" class="drupal_image" /></div>'
			),
			p.post_content
		)
	WHERE p.ID = i.nid
	AND i.field_main_image_fid = f.fid
	AND (
		f.filename LIKE '%.jpg'
		OR f.filename LIKE '%.jpeg'
		OR f.filename LIKE '%.png'
		OR f.filename LIKE '%.gif'
	)
;*/

# main images as featured images for posts
# this will be the default if another version is not present
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', f.filepath) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_field_main_image i using (nid)
		INNER JOIN `minnpost.092515`.files f ON i.field_main_image_fid = f.fid
;

# for audio posts, there is no main image field in Drupal
# for video posts, there is no main image field in Drupal


# use the detail suffix for the single page image
# this loads the detail image from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_detail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/articles', '/imagecache/article_detail/images/articles')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_field_main_image i using (nid)
		INNER JOIN `minnpost.092515`.files f ON i.field_main_image_fid = f.fid
;


# for audio posts, there is no single page image field in Drupal
# for video posts, there is no single page image field in Drupal


# thumbnail version
# this is the small thumbnail from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/thumbnail/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_field_thumbnail_image i using (nid)
		INNER JOIN `minnpost.092515`.files f ON i.field_thumbnail_image_fid = f.fid
;


# thumbnail version for audio posts
# this is the small thumbnail from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_audio a USING (nid)
		INNER JOIN `minnpost.092515`.files f ON a.field_op_audio_thumbnail_fid = f.fid
;


# thumbnail version for video posts
# this is the small thumbnail from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_thumbnail' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_video v USING (nid)
		INNER JOIN `minnpost.092515`.files f ON v.field_op_video_thumbnail_fid = f.fid
;


# might as well use the standard thumbnail meta key with the same value for audio
# wordpress will read this part for us in the admin
# do we need both?
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/thumbnail/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_audio a USING (nid)
		INNER JOIN `minnpost.092515`.files f ON a.field_op_audio_thumbnail_fid = f.fid
;


# might as well use the standard thumbnail meta key with the same value for video
# wordpress will read this part for us in the admin
# do we need both?
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/thumbnail/images/thumbnails/video')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_video v USING (nid)
		INNER JOIN `minnpost.092515`.files f ON v.field_op_video_thumbnail_fid = f.fid
;


# feature thumbnail
# this is the larger thumbnail image from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/articles', '/imagecache/feature/images/thumbnails/articles')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_field_thumbnail_image i using (nid)
		INNER JOIN `minnpost.092515`.files f ON i.field_thumbnail_image_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/articles%'
;


# feature thumbnail for audio posts
# this is the larger thumbnail image from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/audio', '/imagecache/feature/images/thumbnails/audio')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_audio a USING (nid)
		INNER JOIN `minnpost.092515`.files f ON a.field_op_audio_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/audio%'
;


# feature thumbnail for video posts
# this is the larger thumbnail image from cache folder
INSERT IGNORE INTO `minnpost.wordpress`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'_thumbnail_ext_url_feature' `meta_key`,
		CONCAT('https://www.minnpost.com/', REPLACE(f.filepath, '/images/thumbnails/video', '/imagecache/feature/images/thumbnails/video')) `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_video v USING (nid)
		INNER JOIN `minnpost.092515`.files f ON v.field_op_video_thumbnail_fid = f.fid
		WHERE f.filepath LIKE '%images/thumbnails/video%'
;



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

# Miscellaneous clean-up.
# There may be some extraneous blank spaces in your Drupal posts; use these queries
# or other similar ones to strip out the undesirable tags.
UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content,'<p>&nbsp;</p>','')
;
UPDATE `minnpost.wordpress`.wp_posts
	SET post_content = REPLACE(post_content,'<p class="italic">&nbsp;</p>','')
;


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