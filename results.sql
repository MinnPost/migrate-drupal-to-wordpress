# Get count of standard story items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type IN ('article', 'article_full', 'audio', 'video')) as drupal_story_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'post') as wordpress_story_count
;


# find the audio posts
SELECT p.ID, p.post_title, r.term_taxonomy_id, tax.taxonomy
FROM wp_posts p
INNER JOIN wp_term_relationships r ON p.ID = r.object_id
INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
INNER JOIN wp_terms t ON tax.term_id = t.term_id
WHERE t.name = 'post-format-audio'
;

SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.drupal`.node
		WHERE type IN ('audio')
	) as drupal_audio_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN wp_term_relationships r ON p.ID = r.object_id
		INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
		INNER JOIN wp_terms t ON tax.term_id = t.term_id
		WHERE t.name = 'post-format-audio'
	) as wordpress_audio_count
;


# find the video posts
SELECT p.ID, p.post_title, r.term_taxonomy_id, tax.taxonomy
FROM wp_posts p
INNER JOIN wp_term_relationships r ON p.ID = r.object_id
INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
INNER JOIN wp_terms t ON tax.term_id = t.term_id
WHERE t.name = 'post-format-video'
;

SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.drupal`.node
		WHERE type IN ('video')
	) as drupal_video_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN wp_term_relationships r ON p.ID = r.object_id
		INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
		INNER JOIN wp_terms t ON tax.term_id = t.term_id
		WHERE t.name = 'post-format-video'
	) as wordpress_video_count
;


# Get count of standard page items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type IN ('page')) as drupal_page_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'page') as wordpress_page_count
;

# get count of post/category / node/section or node/department combinations
# 1/12/17: this does not match yet
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_relationships r
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
		INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
		WHERE tax.taxonomy = 'category'
	) as wordpress_category_count,
	(
		SELECT
			(SELECT COUNT(DISTINCT nid, field_department_nid)
			FROM `minnpost.drupal`.content_field_department)
			+
			(SELECT COUNT(DISTINCT nid, field_section_nid)
			FROM `minnpost.drupal`.content_field_section)
	) as drupal_combined_count,
	(
		SELECT COUNT(DISTINCT nid, field_department_nid)
		FROM `minnpost.drupal`.content_field_department
	) as drupal_department_count,
	(
		SELECT COUNT(DISTINCT nid, field_section_nid)
		FROM `minnpost.drupal`.content_field_section
	) as drupal_section_count
;


# get count of post/tag / node/term combinations
# this filters wp into tags only
# identical count as of 7/22/16
# 1/11/17 - until today this was incorrect with example of 8,508 posts for tag id 6712.
# it seems to be correct now after fixing the taxonomy id
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_relationships r
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
		INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
		WHERE tax.taxonomy = 'post_tag'
	) as wordpress_tag_count,
	(
		SELECT COUNT(DISTINCT nid, tid)
		FROM `minnpost.drupal`.term_node
	) as drupal_term_count
;

# get name, term id, and count for tag / post pairs
# 1/11/17 - this is broken because the names are wrong
# 1/11/17 - these match now; remember drupal has rows even if there are no posts that have the combination

# Temporary table for the pairs
CREATE TABLE `drupal_term_pairs` (
  `tid` bigint(20) unsigned NOT NULL,
  `name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `count` bigint(20) COLLATE utf8mb4_unicode_ci NOT NULL
);
CREATE TABLE `wordpress_tag_pairs` (
  `tid` bigint(20) unsigned NOT NULL,
  `name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `count` bigint(20) COLLATE utf8mb4_unicode_ci NOT NULL
);

# drupal
INSERT INTO `drupal_term_pairs` (tid, name, count)
	SELECT DISTINCT d.tid, d.name, (
			SELECT COUNT(DISTINCT nid, tid)
			FROM `minnpost.drupal`.term_node
			WHERE tid = d.tid
		) as drupal_term_count
	FROM `minnpost.drupal`.term_data d
	ORDER BY drupal_term_count DESC
;

# wordpress
INSERT INTO `wordpress_tag_pairs` (tid, name, count)
	SELECT t.term_id as tid, t.name as name, 
	(
			SELECT COUNT(*)
			FROM `minnpost.wordpress`.wp_term_relationships r
			WHERE term_taxonomy_id = tax.term_taxonomy_id
		) as wordpress_tag_count
	FROM `minnpost.wordpress`.wp_terms t
	INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON t.term_id = tax.term_id
	WHERE tax.taxonomy = 'post_tag'
	ORDER BY wordpress_tag_count DESC
;

# compare
SELECT DISTINCT tid, name, count
FROM drupal_term_pairs
WHERE tid NOT IN(SELECT tid FROM wordpress_tag_pairs)
AND count > 0
;
SELECT DISTINCT tid, name, count
FROM wordpress_tag_pairs
WHERE tid NOT IN(SELECT tid FROM drupal_term_pairs)
;
# 1/12/17: zero results; drupal does save items even if there are no stories associated with them; we don't need to do that for now

# get rid of those temporary tables
DROP TABLE drupal_pairs;
DROP TABLE wordpress_pairs;


# Get count of comments
# this one has an identical count as of 5/19/16

SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.comments) as drupal_comment_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_comments) as wordpress_comment_count
;


# Get comments that are in Drupal but not in WordPress
# 0 Ids as of 5/19/16

SELECT DISTINCT `minnpost.drupal`.comments.cid
FROM      `minnpost.drupal`.comments
WHERE     `minnpost.drupal`.comments.cid NOT IN(SELECT `minnpost.wordpress`.wp_comments.comment_ID FROM `minnpost.wordpress`.wp_comments)
;


# Get post IDs where the comment count does not match
# as of 5/19/16 there are no results for this query, which is as it should be
# the number changes if we revise a post, as it should

SELECT p.ID as wordpress_id, p.comment_count as wordpress_comment_count, n.nid as drupal_id, (SELECT count(cid) FROM `minnpost.drupal`.comments c WHERE c.nid = n.nid) as drupal_comment_count
FROM `minnpost.wordpress`.wp_posts p
LEFT OUTER JOIN `minnpost.drupal`.node n ON p.ID = n.nid
WHERE p.comment_count != (SELECT count(cid) FROM `minnpost.drupal`.comments c WHERE c.nid = n.nid)
;


# Get count of users
# as of 5/19/16 there is one less user in WordPress.
# this is as it should be

SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.users) as drupal_user_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_users) as wordpress_user_count
;


# Get users that are in Drupal but not in WordPress
# 1 user on 5/19/16; and it is the 0 ID from drupal. we don't need this one.

SELECT DISTINCT `minnpost.drupal`.users.uid
FROM `minnpost.drupal`.users
WHERE `minnpost.drupal`.users.uid NOT IN(
	SELECT `minnpost.wordpress`.wp_users.ID FROM `minnpost.wordpress`.wp_users
)
;



# Get count of authors who are not users
# as of 5/19/16 this is equal

SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type = 'author') as drupal_author_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'guest-author') as wordpress_author_count
;


# Count how many users we added as terms and term_taxonomy
# 2001 users for these queries on 6/29/16; this is correct
# 2018 users for these queries on 1/12/17; this is correct
SELECT COUNT(*) FROM wp_terms WHERE term_group=1;
# also could use this
SELECT count(*) FROM wp_term_taxonomy WHERE taxonomy='author';





# get count of author/story pairs
# as of 5/19/16 these are wildly unequal and it's unclear to me why
# 6/30/16 I thought I fixed it, but nope
# 7/1/16 it is 52754 (drupal) vs 52436 (wordpress)
# 7/6/16 it is 52754 (drupal) vs 52961 (wordpress)
# 7/8/16 is 53316 (drupal) vs 52961 (wordpress)
# count for the insert from drupal into wordpress is 52961
# 7/8/16 final is 52961 for drupal, 52961 for wordpress!!!
# 1/12/17 54901 for drupal, 54901 for wordpress
SELECT
	(
		SELECT COUNT(*)
		FROM
		(
			Select n.nid
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.content_field_op_author a ON n.nid = a.nid
			INNER JOIN `minnpost.drupal`.node auth ON a.field_op_author_nid = auth.nid
			WHERE field_op_author_nid IS NOT NULL
			GROUP BY concat(a.nid, a.field_op_author_nid)
		) as drupal_story_pairs
	) as drupal_post_author_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_relationships r
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON tax.term_taxonomy_id = r.term_taxonomy_id
		WHERE tax.taxonomy = 'author'
	) as wordpress_post_author_count
;



# find the story/author pairs in drupal
#52961
# 1/12/17: 54901 rows
Select a.nid, a.field_op_author_nid
FROM `minnpost.drupal`.content_field_op_author a
INNER JOIN `minnpost.drupal`.node n ON a.nid = n.nid
INNER JOIN `minnpost.drupal`.node auth ON a.field_op_author_nid = auth.nid
WHERE field_op_author_nid IS NOT NULL
GROUP BY concat(a.nid, a.field_op_author_nid)
ORDER BY a.nid


# find the story/author pairs in wordpress
#52961
# can only run this before deleting the user_node_id_old from migrate.sql
SELECT r.object_id, t.user_node_id_old
FROM `minnpost.wordpress`.wp_term_relationships r
INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON tax.term_taxonomy_id = r.term_taxonomy_id
INNER JOIN `minnpost.wordpress`.wp_terms t ON tax.term_id = t.term_id
WHERE tax.taxonomy = 'author'
ORDER BY r.object_id




# this should show us the count of authors per story that are in drupal but not in wordpress
# 7/8/16 zero results
SELECT count(*), au.nid
FROM `minnpost.drupal`.content_field_op_author au
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
	FROM `minnpost.drupal`.content_field_op_author au
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
LEFT OUTER JOIN `minnpost.drupal`.node n ON p.ID = n.nid
LEFT OUTER JOIN `minnpost.drupal`.content_field_op_author a ON n.nid = a.nid
LEFT OUTER JOIN `minnpost.drupal`.node au ON t.name = au.title
WHERE tax.taxonomy = 'author'
AND `minnpost.wordpress`.t.name != au.title
;


# Get count of categories for both systems
# 1/12/17: 75 for each
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.drupal`.node
		WHERE type IN ('department', 'section')
	) as drupal_department_section_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_taxonomy
		WHERE taxonomy = 'category'
	) as wordpress_category_count
;

# need to get a count of tags?
# although we already know the post/tag count