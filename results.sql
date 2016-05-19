# Get count of standard story items in both systems

SELECT
  (SELECT COUNT(*) FROM `minnpost.092515`.node WHERE type IN ('article', 'article_full')) as drupal_story_count, 
  (SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'post') as wordpress_story_count
;

 # Get count of standard page items in both systems

 SELECT
  (SELECT COUNT(*) FROM `minnpost.092515`.node WHERE type IN ('page')) as drupal_page_count, 
  (SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'page') as wordpress_page_count
 ;


 