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


# Get post IDs where the comment count does not match
# as of 5/19/16 there are no results for this query, which is as it should be
# the number changes if we revise a post, as it should

select p.ID as wordpress_id, p.comment_count as wordpress_comment_count, n.nid as drupal_id, (select count(cid) FROM `minnpost.092515`.comments c WHERE c.nid = n.nid) as drupal_comment_count
FROM `minnpost.wordpress`.wp_posts p
LEFT OUTER JOIN `minnpost.092515`.node n ON p.ID = n.nid
WHERE p.comment_count != (select count(cid) FROM `minnpost.092515`.comments c WHERE c.nid = n.nid)
;