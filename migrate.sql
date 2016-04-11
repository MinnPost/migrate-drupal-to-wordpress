# Queries to start fresh

TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_comments;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_links;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_postmeta;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_posts;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_term_relationships;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_term_taxonomy;
TRUNCATE TABLE `minnpost.wordpress.blondish`.wp_terms;

DELETE FROM `minnpost.wordpress.blondish`.wp_users WHERE ID > 1;
DELETE FROM `minnpost.wordpress.blondish`.wp_usermeta WHERE user_id > 1;


# convert tags
REPLACE INTO `minnpost.wordpress.blondish`.wp_terms
(term_id, `name`, slug, term_group)
SELECT DISTINCT
d.tid, d.name, REPLACE(LOWER(d.name), ' ', '_'), 0
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
INSERT INTO `minnpost.wordpress.blondish`.wp_term_taxonomy
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


# convert posts
INSERT INTO `minnpost.wordpress.blondish`.wp_posts
(id, post_author, post_date, post_content, post_title, post_excerpt,
post_name, post_modified, post_type, `post_status`)
SELECT DISTINCT
n.nid `id`,
n.uid `post_author`,
FROM_UNIXTIME(n.created) `post_date`,
r.body `post_content`,
n.title `post_title`,
r.teaser `post_excerpt`,
IF(SUBSTR(a.dst, 11, 1) = '/', SUBSTR(a.dst, 12), a.dst) `post_name`,
FROM_UNIXTIME(n.changed) `post_modified`,
n.type `post_type`,
IF(n.status = 1, 'publish', 'private') `post_status`
FROM `minnpost.092515`.node n
INNER JOIN `minnpost.092515`.node_revisions r
USING(vid)
LEFT OUTER JOIN `minnpost.092515`.url_alias a
ON a.src = CONCAT('node/', n.nid)
# Add more Drupal content types below if applicable.
WHERE n.type IN ('article', 'article_full', 'page')
;

# set post types
UPDATE `minnpost.wordpress.blondish`.wp_posts
SET post_type = 'post'
WHERE post_type IN ('article')
;

# set post types
UPDATE `minnpost.wordpress.blondish`.wp_posts
SET post_type = 'post'
WHERE post_type IN ('article_full')
;

# define the post/tag relationship
INSERT INTO `minnpost.wordpress.blondish`.wp_term_relationships (object_id, term_taxonomy_id)
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

# insert comments
INSERT INTO `minnpost.wordpress.blondish`.wp_comments
(comment_post_ID, comment_date, comment_content, comment_parent, comment_author,
comment_author_email, comment_author_url, comment_approved)
SELECT DISTINCT
nid, FROM_UNIXTIME(timestamp), comment, thread, name,
mail, homepage, ((status + 1) % 2)
FROM `minnpost.092515`.comments
;



# Update comments count on wp_posts table.
UPDATE `minnpost.wordpress.blondish`.wp_posts
SET `comment_count` = (
SELECT COUNT(`comment_post_id`)
FROM `minnpost.wordpress.blondish`.wp_comments
WHERE `minnpost.wordpress.blondish`.wp_posts.`id` = `minnpost.wordpress.blondish`.wp_comments.`comment_post_id`
)
;


# fix file paths in body text
UPDATE `minnpost.wordpress.blondish`.wp_posts SET post_content = REPLACE(post_content, '"/sites/default/files/', '"/wp-content/uploads/');


# supposed to help fix taxonomy
UPDATE IGNORE `minnpost.wordpress.blondish`.wp_term_relationships, `minnpost.wordpress.blondish`.wp_term_taxonomy
SET `minnpost.wordpress.blondish`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.blondish`.wp_term_taxonomy.term_taxonomy_id
WHERE `minnpost.wordpress.blondish`.wp_term_relationships.term_taxonomy_id = `minnpost.wordpress.blondish`.wp_term_taxonomy.term_id
;


# author roles for users
INSERT IGNORE INTO `minnpost.wordpress.blondish`.wp_users
(ID, user_login, user_pass, user_nicename, user_email,
user_registered, user_activation_key, user_status, display_name)
SELECT DISTINCT
u.uid, u.mail, NULL, u.name, u.mail,
FROM_UNIXTIME(created), '', 0, u.name
FROM `minnpost.092515`.users u
INNER JOIN `minnpost.092515`.users_roles r
USING (uid)
WHERE (1
# Uncomment and enter any email addresses you want to exclude below.
# AND u.mail NOT IN ('test@example.com')
)
;



INSERT IGNORE INTO `minnpost.wordpress.blondish`.wp_usermeta (user_id, meta_key, meta_value)
SELECT DISTINCT
u.uid, 'wp_capabilities', 'a:1:{s:6:"author";s:1:"1";}'
FROM `minnpost.092515`.users u
INNER JOIN `minnpost.092515`.users_roles r
USING (uid)
WHERE (1
# Uncomment and enter any email addresses you want to exclude below.
# AND u.mail NOT IN ('test@example.com')
)
;
INSERT IGNORE INTO `minnpost.wordpress.blondish`.wp_usermeta (user_id, meta_key, meta_value)
SELECT DISTINCT
u.uid, 'wp_user_level', '2'
FROM `minnpost.092515`.users u
INNER JOIN `minnpost.092515`.users_roles r
USING (uid)
WHERE (1
# Uncomment and enter any email addresses you want to exclude below.
# AND u.mail NOT IN ('test@example.com')
)
;


# give administrator status
UPDATE `minnpost.wordpress.blondish`.wp_usermeta
SET meta_value = 'a:1:{s:13:"administrator";s:1:"1";}'
WHERE user_id IN (1) AND meta_key = 'wp_capabilities'
;
UPDATE `minnpost.wordpress.blondish`.wp_usermeta
SET meta_value = '10'
WHERE user_id IN (1) AND meta_key = 'wp_user_level'
;



# try to set up authors for posts
UPDATE `minnpost.wordpress.blondish`.wp_posts
SET post_author = NULL
WHERE post_author NOT IN (SELECT DISTINCT ID FROM `minnpost.wordpress.blondish`.wp_users)
;


# cleanup for editor
UPDATE `minnpost.wordpress.blondish`.wp_posts
SET post_name =
REVERSE(SUBSTRING(REVERSE(post_name),1,LOCATE('/',REVERSE(post_name))-1))
;