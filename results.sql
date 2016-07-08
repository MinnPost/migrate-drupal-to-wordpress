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



# Get count of authors who are not users
# as of 5/19/16 this is equal

SELECT
	(SELECT COUNT(*) FROM `minnpost.092515`.node WHERE type = 'author') as drupal_author_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'guest-author') as wordpress_author_count
;


# Count how many users we added as terms and term_taxonomy
# 2001 users for these queries on 6/29/16; this is correct
SELECT COUNT(*) FROM wp_terms WHERE term_group=1;
# also could use this
SELECT count(*) FROM wp_term_taxonomy WHERE taxonomy='author';



# get count of author/story pairs that we think we're adding compared to what is already in drupal
SELECT
  (
	SELECT COUNT(*) AS wordpress_author_story_pairs
	FROM
	(
		SELECT n.nid AS object_id, t.term_id AS term_taxonomy_id
		FROM `minnpost.092515`.node n
		LEFT OUTER JOIN `minnpost.092515`.content_field_op_author author ON n.nid = author.nid
		INNER JOIN `minnpost.wordpress`.wp_terms t ON author.field_op_author_nid = t.user_node_id_old
		WHERE field_op_author_nid IS NOT NULL
		) AS author_story_pairs
	) AS wordpress_story_pairs,
	(
  		SELECT COUNT(*) AS drupal_author_story_pairs
   		FROM
     	(
     		SELECT nid, field_op_author_nid
     		FROM content_field_op_author
     		GROUP BY nid
     		) AS author_story_pairs
     	) AS drupal_story_pairs
  ;


# get count of author/story pairs
# as of 5/19/16 these are wildly unequal and it's unclear to me why

SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.092515`.node n
		LEFT OUTER JOIN `minnpost.092515`.content_field_op_author a ON n.nid = a.nid
		WHERE field_op_author_nid IS NOT NULL
	) as drupal_post_author_count, 
	(
		SELECT COUNT(*) FROM wp_term_relationships r
		INNER JOIN wp_term_taxonomy tax ON tax.term_taxonomy_id = r.term_taxonomy_id
		WHERE tax.taxonomy = 'author'
	) as wordpress_post_author_count
;



# this should show us the count of authors per story that are in drupal but not in wordpress
# 7/8/16 zero results
SELECT count(*), au.nid
FROM `minnpost.092515`.content_field_op_author au
WHERE au.field_op_author_nid IS NOT NULL AND NOT EXISTS
(
	SELECT count(*), r.object_id
	FROM `minnpost.wordpress`.wp_term_relationships r
	WHERE r.object_id = au.nid
	GROUP BY object_id
)
GROUP BY au.nid
;





# this should show us the count of authors per story that are in wordpress but not in drupal
# 7/8/16 zero results
SELECT COUNT(*), r.object_id
FROM `minnpost.wordpress`.wp_term_relationships r
INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
WHERE tax.taxonomy = 'author' AND NOT EXISTS
(
	SELECT COUNT(*), au.nid
	FROM `minnpost.092515`.content_field_op_author au
	WHERE au.field_op_author_nid IS NOT NULL AND au.nid = r.object_id
	GROUP BY au.nid
)
GROUP BY r.object_id
;





# Get post IDs where the author does not match
# as of 5/19/16 there are 333 of these or 2793 if we do not use distinct
# as of 6/30/16 there are 810 of these or 8045 if we do not use distinct. So apparenty getting worse.
# as of 7/1/16 it was 331, and 2789, when trying a different query to create the matches. sigh.
# 7/5/16 - tried going into the WP interface, on one particular article. compared the authors to drupal. there was only one in wp, two in drupal, so added one. this reduced the count in this query as would be expected.
# 7/5/16 reordering the authors in the ui appears to delete both rows
# 7/5/16 has 810 rows, though. no difference between ascending and descending order, apparently
# 7/6/16 - if I use this query instead, joining on the value of the term, no rows are returned. This is as it should be?

SELECT DISTINCT `minnpost.wordpress`.p.ID as wordpress_post_id, `minnpost.wordpress`.t.name as wordpress_author_name, n.nid as drupal_id, au.title as drupal_author_name
FROM `minnpost.wordpress`.wp_posts p
INNER JOIN `minnpost.wordpress`.wp_term_relationships r ON r.object_id = p.ID
INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON tax.term_taxonomy_id = r.term_taxonomy_id
INNER JOIN `minnpost.wordpress`.wp_terms t ON t.term_id = tax.term_id
LEFT OUTER JOIN `minnpost.092515`.node n ON p.ID = n.nid
LEFT OUTER JOIN `minnpost.092515`.content_field_op_author a ON n.nid = a.nid
LEFT OUTER JOIN `minnpost.092515`.node au ON t.name = au.title
WHERE tax.taxonomy = 'author'
AND `minnpost.wordpress`.t.name != au.title
;