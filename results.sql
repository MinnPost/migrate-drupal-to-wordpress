# Get count of standard story items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.node WHERE type IN ('article', 'article_full')) as drupal_story_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'post') as wordpress_story_count
;


# Get count of standard page items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.node WHERE type IN ('page')) as drupal_page_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'page') as wordpress_page_count
;


# Get count of comments
# this one has an identical count as of 5/19/16

SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.comments) as drupal_comment_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_comments) as wordpress_comment_count
;


# Get comments that are in Drupal but not in WordPress
# 0 Ids as of 5/19/16

SELECT DISTINCT `minnpost.092515`.comments.cid
FROM      `minnpost.092515`.comments
WHERE     `minnpost.092515`.comments.cid NOT IN(SELECT `minnpost.wordpress`.wp_comments.comment_ID FROM `minnpost.wordpress`.wp_comments)
;


# Get post IDs where the comment count does not match
# as of 5/19/16 there are no results for this query, which is as it should be
# the number changes if we revise a post, as it should

SELECT p.ID as wordpress_id, p.comment_count as wordpress_comment_count, n.nid as drupal_id, (SELECT count(cid) FROM `minnpost.092515`.comments c WHERE c.nid = n.nid) as drupal_comment_count
FROM `minnpost.wordpress`.wp_posts p
LEFT OUTER JOIN `minnpost.092515`.node n ON p.ID = n.nid
WHERE p.comment_count != (SELECT count(cid) FROM `minnpost.092515`.comments c WHERE c.nid = n.nid)
;


# Get count of users
# as of 5/19/16 there is one less user in WordPress.
# this is as it should be

SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.users) as drupal_user_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_users) as wordpress_user_count
;


# Get users that are in Drupal but not in WordPress
# 1 user on 5/19/16; and it is the 0 ID from drupal. we don't need this one.

SELECT DISTINCT `minnpost.092515`.users.uid
FROM      `minnpost.092515`.users
WHERE     `minnpost.092515`.users.uid NOT IN(SELECT `minnpost.wordpress`.wp_users.ID FROM `minnpost.wordpress`.wp_users)