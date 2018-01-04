# Get count of standard story items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type IN ('article', 'article_full', 'audio', 'video', 'slideshow')) as drupal_story_count, 
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


# find the gallery posts
SELECT p.ID, p.post_title, r.term_taxonomy_id, tax.taxonomy
FROM wp_posts p
INNER JOIN wp_term_relationships r ON p.ID = r.object_id
INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
INNER JOIN wp_terms t ON tax.term_id = t.term_id
WHERE t.name = 'post-format-gallery'
;


# count the slideshow and gallery posts between wordpress and drupal
# 2/8/17: these numbers match
# 1/4/18: there are 208; this is important for line 524
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.drupal`.node
		WHERE type IN ('slideshow')
	) as drupal_gallery_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN wp_term_relationships r ON p.ID = r.object_id
		INNER JOIN wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
		INNER JOIN wp_terms t ON tax.term_id = t.term_id
		WHERE t.name = 'post-format-gallery'
	) as wordpress_gallery_count
;


# need to count the documentcloud items
# 3/29/17: these match
SELECT
	(
		SELECT COUNT(*) FROM (
			SELECT d.nid, field_op_documentcloud_doc_url
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.content_field_op_documentcloud_doc d USING(vid)
			WHERE field_op_documentcloud_doc_url IS NOT NULL
			GROUP BY nid
			ORDER BY nid
		) as documentcloud
	) as drupal_documentcloud_count, 
	(
		SELECT count(*)
		FROM `minnpost.wordpress`.wp_posts
		WHERE post_content LIKE '%documentcloud document%'
	) as wordpress_documentcloud_count
;


# get the image nodes that are in drupal but not wordpress
# 2/21/17: there are 33 of these; only 3 of them have a field_main_image_fid
# 1/4/18: now there are 34, for whatever that's worth.
# i can't tell if this is a problem or not at this point though. if it is, it's a minor problem.
# trying to do more joins seems to cause more problems than it solves.
SELECT nid, title
FROM `minnpost.drupal`.node n
WHERE n.type = 'op_image'
AND n.nid NOT IN (SELECT ID FROM `minnpost.wordpress`.wp_posts WHERE n.nid = ID)


# count thumbnails tied to posts
# wordpress: 29011
SELECT ID, meta_value
FROM wp_postmeta m
LEFT OUTER JOIN wp_posts p ON m.post_id = p.ID
WHERE meta_key = '_mp_post_thumbnail_image_id' AND meta_value IS NOT NULL AND ID IS NOT NULL
GROUP BY ID
ORDER BY ID
;


# drupal: 25230
SELECT n.nid as ID, CONCAT('https://www.minnpost.com/', f.filepath) as meta_value
FROM `minnpost.drupal`.content_field_thumbnail_image i
LEFT OUTER JOIN `minnpost.drupal`.node n USING(nid)
LEFT OUTER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
WHERE n.type IN ('article', 'article_full', 'audio', 'page', 'video', 'slideshow')
AND i.field_thumbnail_image_fid IS NOT NULL AND n.nid IS NOT NULL
GROUP BY n.nid
ORDER BY ID
;

# find missing ones from drupal
SELECT ID, meta_value
FROM wp_postmeta m
LEFT OUTER JOIN wp_posts p ON m.post_id = p.ID
WHERE meta_key = '_mp_post_thumbnail_image_id' AND meta_value IS NOT NULL AND ID IS NOT NULL
AND NOT EXISTS (
	SELECT n.nid as ID, CONCAT('https://www.minnpost.com/', f.filepath) as meta_value
	FROM `minnpost.drupal`.content_field_thumbnail_image i
	LEFT OUTER JOIN `minnpost.drupal`.node n USING(nid)
	LEFT OUTER JOIN `minnpost.drupal`.files f ON i.field_thumbnail_image_fid = f.fid
	WHERE n.type IN ('article', 'article_full', 'audio', 'page', 'video', 'slideshow')
	AND i.field_thumbnail_image_fid IS NOT NULL AND n.nid IS NOT NULL
	GROUP BY n.nid
	ORDER BY ID
)
GROUP BY ID
ORDER BY ID;


# get homepage image sizes
# 4/4/17: equal numbers here
SELECT	
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_postmeta
		WHERE meta_key = '_mp_post_homepage_image_size'
	) as wordpress_homepage_image_count,
	(
		SELECT COUNT(DISTINCT nid, field_hp_image_size_value) 
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_hp_image_size d USING(nid, vid)
		WHERE field_hp_image_size_value IS NOT NULL
	) as drupal_homepage_image_count
;


# count deck fields
# 4/4/17: equal numbers here
SELECT
	(
		SELECT COUNT(DISTINCT d.nid, d.field_deck_value)
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_deck d USING(nid, vid)
		WHERE d.field_deck_value IS NOT NULL
	) as drupal_deck_count,
	(
		SELECT count(*)
		FROM `minnpost.wordpress`.wp_postmeta
		WHERE meta_key = '_mp_subtitle_settings_deck'
	) as wordpress_deck_count
;


# count byline fields
# 4/4/17: equal numbers here
SELECT
	(
		SELECT COUNT(DISTINCT b.nid, b.field_byline_value)
		FROM `minnpost.drupal`.node n
		INNER JOIN `minnpost.drupal`.node_revisions r USING(nid, vid)
		INNER JOIN `minnpost.drupal`.content_field_byline b USING(nid, vid)
		WHERE b.field_byline_value IS NOT NULL
	) as drupal_byline_count,
	(
		SELECT count(*)
		FROM `minnpost.wordpress`.wp_postmeta
		WHERE meta_key = '_mp_subtitle_settings_byline'
	) as wordpress_byline_count
;


# Get count of standard page items
# this one has an identical count as of 5/19/16
SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type IN ('page')) as drupal_page_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'page') as wordpress_page_count
;


# Get count of newsletter items
# this one has an identical count as of 7/20/17
SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.node WHERE type IN ('newsletter')) as drupal_newsletter_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_posts WHERE post_type = 'newsletter') as wordpress_newsletter_count
;


# Get count of newsletters by type
# these are identical as of 7/20/17

# drupal
# 1633, 272, 1, 193, 11
# 1/4/18: 1746, 291, 1, 213, 29
SELECT td.name, COUNT(*)
	FROM `minnpost.drupal`.node n
	INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
	INNER JOIN `minnpost.drupal`.term_node tn USING(nid, vid)
	INNER JOIN `minnpost.drupal`.term_data td USING(tid)
	WHERE type IN ('newsletter')
	GROUP BY tn.tid
;

# wordpress
# 1633, 272, 1, 193, 11
# 1/4/18: 1746, 291, 1, 213, 29
SELECT m.meta_value, count(*)
	FROM `minnpost.wordpress`.wp_posts p
	INNER JOIN `minnpost.wordpress`.wp_postmeta m ON p.ID = m.post_id
	WHERE p.post_type = 'newsletter' AND m.meta_key = '_mp_newsletter_type'
	GROUP BY m.meta_value
	ORDER BY m.meta_id
;


# Get count of categories (wp) and department/section nodes (drupal)
# 1/12/17: 75 for each
# 3/23/17: 76 wordpress categories because we had to add one for galleries; wordpress won't create permalinks otherwise
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

# get all the pairs between articles and section/department nodes in drupal
# 2/2/17: 108724
# 2/7/17: 108983
# 2/7/17: 107980 with group by title/category
# 3/23/17: 107987
# 5/15/17: 108158
# 1/4/18: 110924
SELECT DISTINCT d.nid as nid, d.field_department_nid as category, n.title as title, d2.title as category_title
FROM `minnpost.drupal`.node n
INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
INNER JOIN `minnpost.drupal`.content_field_department d USING (nid, vid)
INNER JOIN `minnpost.drupal`.node d2 ON d.field_department_nid = d2.nid
WHERE d.nid IS NOT NULL AND d.field_department_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
GROUP BY title, category_title
UNION
SELECT DISTINCT s.nid as nid, s.field_section_nid as category, n.title as title, s2.title as category_title
FROM `minnpost.drupal`.node n
INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
INNER JOIN `minnpost.drupal`.content_field_section s USING (nid, vid)
INNER JOIN `minnpost.drupal`.node s2 ON s.field_section_nid = s2.nid
WHERE s.nid IS NOT NULL AND s.field_section_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
GROUP BY title, category_title;


# get all the pairs between posts and categories in wordpress
# 2/2/17: 108438
# 2/7/17: 108711
# 2/7/17: 107703 with group by title/category
# 3/23/17: 107833
# 5/15/17: 108022
# 1/4/18: 111107
SELECT p.ID, t.term_id, p.post_title, t.name
FROM `minnpost.wordpress`.wp_term_relationships r
INNER JOIN `minnpost.wordpress`.wp_posts p ON r.object_id = p.ID
INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
WHERE tax.taxonomy = 'category'
GROUP BY post_title, name
ORDER BY post_title, name
;


# get the pairs from drupal that are not in wordpress
# 2/2/17: 0 results
# 2/6/17: this is confusing because the above queries result in a difference of 272
# 5/15/17: still 0 results
# 5/15/17: still has a difference in the above query counts of 136
# 1/4/18: still difference of zero
SELECT DISTINCT d.nid as nid, d.field_department_nid as category, n.title as title, d2.title as category_title
FROM `minnpost.drupal`.node n
INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
INNER JOIN `minnpost.drupal`.content_field_department d USING (nid, vid)
INNER JOIN `minnpost.drupal`.node d2 ON d.field_department_nid = d2.nid
WHERE d.nid IS NOT NULL AND d.field_department_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
AND NOT EXISTS (
	SELECT p.ID, t.term_id, p.post_title, t.name
	FROM `minnpost.wordpress`.wp_term_relationships r
	INNER JOIN `minnpost.wordpress`.wp_posts p ON r.object_id = p.ID
	INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
	INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
	WHERE tax.taxonomy = 'category'
	ORDER BY p.ID, name
)
UNION
SELECT DISTINCT s.nid as nid, s.field_section_nid as category, n.title as title, s2.title as category_title
FROM `minnpost.drupal`.node n
INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
INNER JOIN `minnpost.drupal`.content_field_section s USING (nid, vid)
INNER JOIN `minnpost.drupal`.node s2 ON s.field_section_nid = s2.nid
WHERE s.nid IS NOT NULL AND s.field_section_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
AND NOT EXISTS (
	SELECT p.ID, t.term_id, p.post_title, t.name
	FROM `minnpost.wordpress`.wp_term_relationships r
	INNER JOIN `minnpost.wordpress`.wp_posts p ON r.object_id = p.ID
	INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
	INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
	WHERE tax.taxonomy = 'category'
	ORDER BY p.ID, name
)
ORDER BY nid, category_title
;


# get the pairs from wordpress that are not in drupal
# 2/3/17: 0 results
# 3/23/17: still has 0 results, even though that maybe shouldn't be accurate now because of the gallery posts?
# 5/15/17: still has 0 apparently
# 1/4/18: still has 0 apparently
SELECT p.ID, t.term_id, p.post_title, t.name
FROM `minnpost.wordpress`.wp_term_relationships r
INNER JOIN `minnpost.wordpress`.wp_posts p ON r.object_id = p.ID
INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
WHERE tax.taxonomy = 'category'
AND NOT EXISTS (
	SELECT DISTINCT d.nid as nid, d.field_department_nid as category, n.title as title, d2.title as category_title
	FROM `minnpost.drupal`.node n
	INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
	INNER JOIN `minnpost.drupal`.content_field_department d USING (nid, vid)
	INNER JOIN `minnpost.drupal`.node d2 ON d.field_department_nid = d2.nid
	WHERE d.nid IS NOT NULL AND d.field_department_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
	GROUP BY title, category_title
	UNION
	SELECT DISTINCT s.nid as nid, s.field_section_nid as category, n.title as title, s2.title as category_title
	FROM `minnpost.drupal`.node n
	INNER JOIN `minnpost.drupal`.node_revisions nr USING (nid, vid)
	INNER JOIN `minnpost.drupal`.content_field_section s USING (nid, vid)
	INNER JOIN `minnpost.drupal`.node s2 ON s.field_section_nid = s2.nid
	WHERE s.nid IS NOT NULL AND s.field_section_nid IS NOT NULL AND n.type IN ('article', 'article_full', 'audio', 'video', 'slideshow')
	GROUP BY title, category_title
)
ORDER BY p.ID, name
;


# get count of post/category / node/section or node/department combinations
# this filters wp into categories only
# 2/1/17: not working; 108775 for wordpress, 106914 for drupal
# 5/15/17: 109415 for wp, 109468 for drupal
# 1/4/18: wp: 112514; drupal: 112311
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_relationships r
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax USING(term_taxonomy_id)
		INNER JOIN `minnpost.wordpress`.wp_terms t USING(term_id)
		WHERE tax.taxonomy = 'category'
	) as wordpress_category_count,
	(
		SELECT COUNT(*) FROM (
			SELECT DISTINCT d.nid as nid, d.field_department_nid as category
				FROM `minnpost.drupal`.node n
				INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
				INNER JOIN `minnpost.drupal`.content_field_department d USING(nid, vid)
				WHERE d.nid IS NOT NULL AND d.field_department_nid IS NOT NULL
				UNION
				SELECT DISTINCT s.nid as nid, s.field_section_nid as category
				FROM `minnpost.drupal`.node n
				INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
				INNER JOIN `minnpost.drupal`.content_field_section s USING(nid, vid)
				WHERE s.nid IS NOT NULL AND s.field_section_nid IS NOT NULL
				ORDER BY nid
		) pairs
	) as drupal_category_count
;


# get name, term id, and count for category / post pairs compared to section/department / node pairs
# 2/1/17: these match
# 5/15/17: these no longer match.
# however, i think this is necessary because we're no longer saving all the old revisions
# this means a wordpress post will only have the categories that the active revision has in drupal
# this also means i can't think of a good way to test the counts anymore.


# Temporary table for the story/category pairs
CREATE TABLE `drupal_section_department_pairs` (
	`tid` bigint(11) unsigned NOT NULL,
	`name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`count` bigint(11) NOT NULL,
	UNIQUE KEY `tid` (`tid`,`name`)
);
CREATE TABLE `wordpress_category_pairs` (
	`tid` bigint(11) unsigned NOT NULL,
	`name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
	`count` bigint(11) COLLATE utf8mb4_unicode_ci NOT NULL
);

# save how many stories exist in each drupal department and section

# section
INSERT IGNORE INTO drupal_section_department_pairs (tid, name, count)
	SELECT nid as tid, title as name, count(1) as count
	FROM (
	    SELECT DISTINCT 'Sect' as DeptOrSect, sect.nid, sect.title, link.nid as article_nid
	    FROM `minnpost.drupal`.node sect
	    JOIN `minnpost.drupal`.content_field_section link ON link.field_section_nid = sect.nid
	    UNION ALL
	    SELECT DISTINCT
	        'Dept' as DeptOrSect,
	        dept.nid,
	        dept.title,
	        link.nid as article_nid
	    FROM `minnpost.drupal`.node dept
	    JOIN `minnpost.drupal`.content_field_department link ON link.field_department_nid = dept.nid
	    WHERE NOT EXISTS (
	        SELECT DISTINCT 1
	        FROM `minnpost.drupal`.content_field_section sect
	        WHERE sect.nid = link.nid
	    )
	) as x
	WHERE DeptOrSect = 'Sect'
	GROUP BY DeptOrSect, nid, title
	ORDER BY count DESC
;

# department
INSERT IGNORE INTO drupal_section_department_pairs (tid, name, count)
	SELECT nid as tid, title as name, count(1) as count
	FROM (
	    SELECT DISTINCT 'DEPT' as DeptOrSect, dept.nid, dept.title, link.nid as article_nid
	    FROM `minnpost.drupal`.node dept
	    JOIN `minnpost.drupal`.content_field_department link ON link.field_department_nid = dept.nid
	    UNION ALL
	    SELECT DISTINCT 'SECT' as DeptOrSect, sect.nid, sect.title, link.nid as article_nid
	    FROM `minnpost.drupal`.node sect
	    JOIN `minnpost.drupal`.content_field_section link ON link.field_section_nid = sect.nid
	    WHERE NOT EXISTS (
	        SELECT DISTINCT 1
	        FROM `minnpost.drupal`.content_field_department dept
	        WHERE dept.nid = link.nid
	    )
	) as x
	WHERE DeptOrSect = 'Dept'
	GROUP BY DeptOrSect, nid, title
	ORDER BY count DESC
;


# save how many posts exist in each wordpress category
INSERT IGNORE INTO wordpress_category_pairs (tid, name, count)
	SELECT t.term_id as tid, t.name as name, 
	(
			SELECT COUNT(*)
			FROM `minnpost.wordpress`.wp_term_relationships r
			WHERE term_taxonomy_id = tax.term_taxonomy_id
		) as wordpress_category_count
	FROM `minnpost.wordpress`.wp_terms t
	INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON t.term_id = tax.term_id
	WHERE tax.taxonomy = 'category'
	ORDER BY wordpress_category_count DESC
;


# compare
SELECT DISTINCT tid, name, count
FROM drupal_section_department_pairs
WHERE name NOT IN(SELECT name FROM wordpress_category_pairs)
AND count > 0
;
SELECT DISTINCT tid, name, count
FROM wordpress_category_pairs
WHERE name NOT IN(SELECT name FROM drupal_section_department_pairs)
;
# 2/1/17: zero results
# 3/23/17: still zero results; this should be wrong though i think with the galleries
# 5/15/17: still zero
# 1/4/18: now it is 208 gallery posts only. i think that is actually right. reference line 73


# get rid of those temporary tables
DROP TABLE drupal_section_department_pairs;
DROP TABLE wordpress_category_pairs;



# Get count of tags (wp) and terms (drupal)
# 1/12/17: 7810 for each
SELECT
	(
		SELECT COUNT(*)
		FROM `minnpost.drupal`.term_data
	) as drupal_term_count, 
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_term_taxonomy
		WHERE taxonomy = 'post_tag'
	) as wordpress_tag_count
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
DROP TABLE drupal_term_pairs;
DROP TABLE wordpress_tag_pairs;


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
# 1/4/18: now we don't add the verified spam users to wordpress, so it is a bit less in wordpress

SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.users) as drupal_user_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_users) as wordpress_user_count
;


# Get users that are in Drupal but not in WordPress
# 1 user on 5/19/16; and it is the 0 ID from drupal. we don't need this one.
# 1/4/18: 9735 spam users now, and the 0 id from drupal.

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
# 1/4/18: 2033 of these now; that is fine.
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
# 5/15/17: 55577 for drupal, 55577 for wordpress - we are tracking the revisions accurately now
SELECT
	(
		SELECT COUNT(*)
		FROM
		(
			SELECT n.nid
			FROM `minnpost.drupal`.node n
			INNER JOIN `minnpost.drupal`.node_revisions nr USING(nid, vid)
			INNER JOIN `minnpost.drupal`.content_field_op_author a USING(nid, vid)
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
INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
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


# Get count of url redirects
# as of 1/26/17 this is equal
# 3/23/17: there are 209 gallery redirects because that's how many gallery redirects we have to create

SELECT
	(SELECT COUNT(*) FROM `minnpost.drupal`.path_redirect) as drupal_redirect_count, 
	(SELECT COUNT(*) FROM `minnpost.wordpress`.wp_redirection_items) as wordpress_redirect_count,
	(
		SELECT COUNT(*)
		FROM `minnpost.wordpress`.wp_posts p
		INNER JOIN `minnpost.wordpress`.wp_term_relationships r ON p.ID = r.object_id
		INNER JOIN `minnpost.wordpress`.wp_term_taxonomy tax ON r.term_taxonomy_id = tax.term_taxonomy_id
		INNER JOIN `minnpost.wordpress`.wp_terms t ON t.term_id = tax.term_id
		WHERE t.slug = 'galleries'
	) as wordpress_gallery_redirect_count
;