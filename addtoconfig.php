// run each group separately or it will crash



// posts

// We prepare a variable to hold arrays with post titles so we don't accidentally make duplicates, that would be bad
$slug_done = array();
// Run a query to grab all the posts, we only want posts/pages though
$posts = $wpdb->get_results( "
SELECT
`ID`,
`post_title`
FROM
`" . $wpdb->posts . "`
WHERE
`post_status` = 'publish'
AND (
`post_type` = 'page'
OR
`post_type` = 'post'
)
" );
// Loop through results
foreach( $posts AS $single )
{
// Generate a URL friendly slug from the title
$slug_base = sanitize_title_with_dashes( $single->post_title );
$this_slug = $slug_base;
$slug_num = 1;
// Check if the slug already exists, if it does, we add an incremental integer ot the end of it
while (in_array( $this_slug, $slug_done ) )
{
$this_slug = $slug_base . '-' . $slug_num;
$slug_num++;
}
$slug_done[] = $this_slug;
// We are happy with our slug, update the database table
$wpdb->query( "
UPDATE
`" . $wpdb->posts . "`
SET
`post_name` = '" . $this_slug . "'
WHERE
`ID` = '" . $single->ID . "'
LIMIT 1
" );
}




// terms


$terms = $wpdb->get_results( "
SELECT
`term_id`,
`name`
FROM
`" . $wpdb->terms . "`
" );


// Loop through results
foreach( $terms AS $term )
{
// Generate a URL friendly slug from the name
$slug_base = sanitize_title_with_dashes( $term->name );
$this_slug = $slug_base;
$slug_num = 1;
// Check if the slug already exists, if it does, we add an incremental integer to the end of it
while (in_array( $this_slug, $slug_done ) )
{
$this_slug = $slug_base . '-' . $slug_num;
$slug_num++;
}
$slug_done[] = $this_slug;
// We are happy with our slug, update the database table
$wpdb->query( "
UPDATE
`" . $wpdb->terms . "`
SET
`slug` = '" . $this_slug . "'
WHERE
`term_id` = '" . $term->term_id . "'
LIMIT 1
" );
}