# DRUPAL-TO-WORDPRESS CONVERSION SCRIPT

# Changelog

# 07.29.2010 - Updated by Scott Anderson / Room 34 Creative Services http://blog.room34.com/archives/4530
# 02.06.2009 - Updated by Mike Smullin http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/
# 05.15.2007 - Updated by D’Arcy Norman http://www.darcynorman.net/2007/05/15/how-to-migrate-from-drupal-5-to-wordpress-2/
# 05.19.2006 - Created by Dave Dash http://spindrop.us/2006/05/19/migrating-from-drupal-47-to-wordpress/

# This assumes that WordPress and Drupal are in separate databases, named 'wordpress' and 'drupal'.
# If your database names differ, adjust these accordingly.

# Empty previous content from WordPress database.
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_comments;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_links;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_postmeta;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_posts;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_term_relationships;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_term_taxonomy;
TRUNCATE TABLE `minnpost.wordpress.underdog`.wp_terms;

# If you're not bringing over multiple Drupal authors, comment out these lines and the other
# author-related queries near the bottom of the script.
# This assumes you're keeping the default admin user (user_id = 1) created during installation.
DELETE FROM `minnpost.wordpress.underdog`.wp_users WHERE ID > 1;
DELETE FROM `minnpost.wordpress.underdog`.wp_usermeta WHERE user_id > 1;


# Tags from Drupal vocabularies
# Using REPLACE prevents script from breaking if Drupal contains duplicate terms.
# permalinks are going to break for tags whatever we do, because drupal puts them all into folders (ie https://www.minnpost.com/category/social-tags/architect)
# we have to determine which tags should instead be (or already are) categories, so we don't have permalinks like books-1

REPLACE INTO `minnpost.wordpress.underdog`.wp_terms
	(term_id, `name`, slug, term_group)
	SELECT DISTINCT
		d.tid, d.name, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(d.name), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', ''), 0
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


# Taxonomy for tags
# creates a taxonomy item for each tag
INSERT INTO `minnpost.wordpress.underdog`.wp_term_taxonomy
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
INSERT INTO `minnpost.wordpress.underdog`.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_modified, post_type, `post_status`)
	SELECT DISTINCT
		n.nid `id`,
		n.uid `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		r.body `post_content`,
		n.title `post_title`,
		r.teaser `post_excerpt`,
		REPLACE(IF(SUBSTR(a.dst, 11, 1) = '/', SUBSTR(a.dst, 12), a.dst), '%e2%80%99', '-') `post_name`,
		FROM_UNIXTIME(n.changed) `post_modified`,
		n.type `post_type`,
		IF(n.status = 1, 'publish', 'draft') `post_status`
	FROM `minnpost.092515`.node n
	INNER JOIN `minnpost.092515`.node_revisions r
		USING(vid)
	LEFT OUTER JOIN `minnpost.092515`.url_alias a
		ON a.src = CONCAT('node/', n.nid)
	# Add more Drupal content types below if applicable.
	WHERE n.type IN ('article', 'article_full', 'page')
;

# Fix post type; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-17826
# Add more Drupal content types below if applicable.
UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET post_type = 'post'
	WHERE post_type IN ('article', 'article_full')
;

# Set all pages to "pending".
# If you're keeping the same page structure from Drupal, comment out this query
# and the new page INSERT at the end of this script.
# UPDATE `minnpost.wordpress.underdog`.wp_posts SET post_status = 'pending' WHERE post_type = 'page';

# Post/Tag relationships
INSERT INTO `minnpost.wordpress.underdog`.wp_term_relationships (object_id, term_taxonomy_id)
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
INSERT INTO `minnpost.wordpress.underdog`.wp_comments
	(comment_post_ID, comment_date, comment_content, comment_parent, comment_author,
	comment_author_email, comment_author_url, comment_approved)
	SELECT DISTINCT
		nid, FROM_UNIXTIME(timestamp), comment, thread, name,
		mail, homepage, ((status + 1) % 2)
	FROM `minnpost.092515`.comments
;

# Update comments count on wp_posts table.
UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET `comment_count` = (
		SELECT COUNT(`comment_post_id`)
		FROM `minnpost.wordpress.underdog`.wp_comments
		WHERE `minnpost.wordpress.underdog`.wp_posts.`id` = `minnpost.wordpress.underdog`.wp_comments.`comment_post_id`
	)
;

# Fix images in post content; uncomment if you're moving files from "files" to "wp-content/uploads".
# in our case, we use this to make the urls absolute, at least for now
#UPDATE `minnpost.wordpress.underdog`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"/wp-content/uploads/');
UPDATE `minnpost.wordpress.underdog`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"https://www.minnpost.com/sites/default/files/')
;

# Fix taxonomy; http://www.mikesmullin.com/development/migrate-convert-import-drupal-5-to-wordpress-27/#comment-27140
UPDATE IGNORE `minnpost.wordpress.underdog`.wp_term_relationships, `minnpost.wordpress.underdog`.wp_term_taxonomy
	SET `minnpost.wordpress.underdog`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.underdog`.wp_term_taxonomy.term_taxonomy_id
	WHERE `minnpost.wordpress.underdog`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.underdog`.wp_term_taxonomy.term_id
;

# OPTIONAL ADDITIONS -- REMOVE ALL BELOW IF NOT APPLICABLE TO YOUR CONFIGURATION

# CATEGORIES
# These are NEW categories, not in `minnpost.092515`. Add as many sets as needed.
#INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_terms (name, slug)
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
INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_terms_dept (term_id, name, slug)
	SELECT nid, title, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(title), '-the-', '-'), '-the', ''), 'the-', ''), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', '')
	FROM `minnpost.092515`.node WHERE type='department'
;


# Put all Drupal departments into terms; store old term ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, term_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_dept d
;


# Create taxonomy for each department
INSERT INTO `minnpost.wordpress.underdog`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id, 'category' FROM wp_terms WHERE term_id_old IS NOT NULL
;

# Create relationships for each story to the deparments it had in Drupal
# Track this relationship by the term_id_old field
INSERT INTO `minnpost.wordpress.underdog`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT dept.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id from wp_term_taxonomy tax
	INNER JOIN wp_terms term ON tax.term_id = term.term_id
	INNER JOIN `minnpost.092515`.content_field_department dept ON term.term_id_old = dept.field_department_nid
	WHERE tax.taxonomy = 'category'
;

# Empty term_id_old values so we can start over with our auto increment and still track for sections
UPDATE `minnpost.wordpress.underdog`.wp_terms SET term_id_old = NULL;

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
INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_terms_section (term_id, name, slug)
	SELECT nid, title, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(title), '-the-', '-'), '-the', ''), 'the-', ''), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', '')
	FROM `minnpost.092515`.node WHERE type='section'
;


# Put all Drupal sections into terms; store old term ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, term_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_section s
;


# Create taxonomy for each section
INSERT INTO `minnpost.wordpress.underdog`.wp_term_taxonomy (term_id, taxonomy)
	SELECT term_id, 'category' FROM wp_terms WHERE term_id_old IS NOT NULL
;


# Create relationships for each story to the section it had in Drupal
# Track this relationship by the term_id_old field
INSERT INTO `minnpost.wordpress.underdog`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT DISTINCT section.nid as object_id, tax.term_taxonomy_id as term_taxonomy_id from wp_term_taxonomy tax
	INNER JOIN wp_terms term ON tax.term_id = term.term_id
	INNER JOIN `minnpost.092515`.content_field_section section ON term.term_id_old = section.field_section_nid
	WHERE tax.taxonomy = 'category'
;


# Empty term_id_old values so we can start over with our auto increment if applicable
UPDATE `minnpost.wordpress.underdog`.wp_terms SET term_id_old = NULL;

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
UPDATE IGNORE `minnpost.wordpress.underdog`.wp_term_relationships, `minnpost.wordpress.underdog`.wp_term_taxonomy
	SET `minnpost.wordpress.underdog`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.underdog`.wp_term_taxonomy.term_taxonomy_id
	WHERE `minnpost.wordpress.underdog`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.underdog`.wp_term_taxonomy.term_id
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
INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_users
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
INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_usermeta (user_id, meta_key, meta_value)
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

INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_usermeta (user_id, meta_key, meta_value)
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


# Drupal authors who are not users
# these get inserted as posts with a type of guest-author, for the plugin
INSERT INTO `minnpost.wordpress.underdog`.wp_posts
	(id, post_author, post_date, post_content, post_title, post_excerpt,
	post_name, post_modified, post_type, `post_status`)
	SELECT DISTINCT
		n.nid `id`,
		1 `post_author`,
		FROM_UNIXTIME(n.created) `post_date`,
		'' `post_content`,
		n.title `post_title`,
		'' `post_excerpt`,
		CONCAT('cap-', REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(n.title), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', '')) `post_name`,
		FROM_UNIXTIME(n.changed) `post_modified`,
		'guest-author' `post_type`,
		'publish' `post_status`
	FROM `minnpost.092515`.node n
	INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
;

# add the user_node_id_old field for tracking Drupal node IDs for non-user authors
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

INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_terms_users (term_id, name, slug)
	SELECT DISTINCT nid, title, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(title), '-the-', '-'), '-the', ''), 'the-', ''), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', '')
	FROM `minnpost.092515`.node WHERE type='author'
;

# Put all Drupal authors into terms; store old node ID from Drupal for tracking relationships
INSERT INTO wp_terms (name, slug, term_group, user_node_id_old)
	SELECT name, slug, term_group, term_id
	FROM wp_terms_users u
;

# get rid of that temporary author table
DROP TABLE wp_terms_users;

# Create taxonomy for each author
INSERT INTO `minnpost.wordpress.underdog`.wp_term_taxonomy (term_id, taxonomy, description)
	SELECT term_id, 'author', CONCAT(p.post_title, ' ', t.name, ' ', p.ID) as description
	FROM wp_terms t
	INNER JOIN wp_posts p ON t.`user_node_id_old` = p.ID
;

# Create relationships for each story to the author it had in Drupal
# Track this relationship by the user_node_id_old field
INSERT IGNORE INTO `minnpost.wordpress.underdog`.wp_term_relationships(object_id, term_taxonomy_id)
	SELECT nid as object_id, tax.term_taxonomy_id as term_taxonomy_id
	FROM `minnpost.092515`.content_field_op_author author
	INNER JOIN `minnpost.wordpress.underdog`.wp_terms t ON t.user_node_id_old = author.field_op_author_nid
	INNER JOIN `minnpost.wordpress.underdog`.wp_term_taxonomy tax ON t.term_id = tax.term_id
	INNER JOIN `minnpost.wordpress.underdog`.wp_posts p ON author.nid = p.Id
	WHERE field_op_author_nid IS NOT NULL
	GROUP BY object_id
;

# use the title as the user's display name
# this might be all the info we have about them
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-display_name' `meta_key`,
		n.title `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
;

# make a slug for user's login
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
	(post_id, meta_key, meta_value)
	SELECT DISTINCT
		n.nid `post_id`,
		'cap-user_login' `meta_key`,
		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(n.title), ' ', '-'), '&', ''), '--', '-'), ';', ''), '.', ''), ',', ''), '/', '') `meta_value`
		FROM `minnpost.092515`.node n
		INNER JOIN `minnpost.092515`.content_type_author author USING (nid)
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
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
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
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
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
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
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
INSERT INTO `minnpost.wordpress.underdog`.wp_postmeta
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
UPDATE `minnpost.wordpress.underdog`.wp_usermeta
	SET meta_value = 'a:1:{s:13:"administrator";s:1:"1";}'
	WHERE user_id IN (1) AND meta_key = 'wp_capabilities'
;
UPDATE `minnpost.wordpress.underdog`.wp_usermeta
	SET meta_value = '10'
	WHERE user_id IN (1) AND meta_key = 'wp_user_level'
;

# Reassign post authorship.
UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET post_author = NULL
	WHERE post_author NOT IN (SELECT DISTINCT ID FROM `minnpost.wordpress.underdog`.wp_users)
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
# UPDATE `minnpost.wordpress.underdog`.wp_posts AS posts INNER JOIN `minnpost.092515`.content_field_op_author AS authors ON posts.ID = authors.nid SET posts.post_author = authors.field_op_author_nid;

# get rid of that user_node_id_old field if we are done migrating into wp_term_relationships
ALTER TABLE wp_terms DROP COLUMN user_node_id_old;

# VIDEO - READ BELOW AND COMMENT OUT IF NOT APPLICABLE TO YOUR SITE
# If your Drupal site uses the content_field_video table to store links to YouTube videos,
# this query will insert the video URLs at the end of all relevant posts.
# WordPress will automatically convert the video URLs to YouTube embed code.
#UPDATE IGNORE `minnpost.wordpress.underdog`.wp_posts p, `minnpost.092515`.content_field_video v
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
UPDATE IGNORE `minnpost.wordpress.underdog`.wp_posts p, `minnpost.092515`.content_field_main_image i, `minnpost.092515`.files f
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
;

# Fix post_name to remove paths.
# If applicable; Drupal allows paths (i.e. slashes) in the dst field, but this breaks
# WordPress URLs. If you have mod_rewrite turned on, stripping out the portion before
# the final slash will allow old site links to work properly, even if the path before
# the slash is different!

# this does not seem to be useful for us

/*UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET post_name =
	REVERSE(SUBSTRING(REVERSE(post_name),1,LOCATE('/',REVERSE(post_name))-1))
;*/

# Miscellaneous clean-up.
# There may be some extraneous blank spaces in your Drupal posts; use these queries
# or other similar ones to strip out the undesirable tags.
UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET post_content = REPLACE(post_content,'<p>&nbsp;</p>','')
;
UPDATE `minnpost.wordpress.underdog`.wp_posts
	SET post_content = REPLACE(post_content,'<p class="italic">&nbsp;</p>','')
;

# NEW PAGES - READ BELOW AND COMMENT OUT IF NOT APPLICABLE TO YOUR SITE
# MUST COME LAST IN THE SCRIPT AFTER ALL OTHER QUERIES!
# If your site will contain new pages, you can set up the basic structure for them here.
# Once the import is complete, go into the WordPress admin and copy content from the Drupal
# pages (which are set to "pending" in a query above) into the appropriate new pages.
#INSERT INTO `minnpost.wordpress.underdog`.wp_posts
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