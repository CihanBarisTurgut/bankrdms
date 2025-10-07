CREATE OR REPLACE FUNCTION get_list_card_type_func()
RETURNS SETOF card_type
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM card_type
    ORDER BY card_type_id;
END;
$$;
