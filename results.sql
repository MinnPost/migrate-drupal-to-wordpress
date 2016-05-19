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
# count as of 5/19/16 is:
## drupal: 186,036
## wordpress: 185,958

SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.comments) as drupal_comment_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_comments) as wordpress_comment_count
;