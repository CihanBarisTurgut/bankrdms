CREATE OR REPLACE FUNCTION get_list_card_func()
RETURNS SETOF card
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM card
    ORDER BY card_id;
END;
$$;