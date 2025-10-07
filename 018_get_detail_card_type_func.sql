CREATE OR REPLACE FUNCTION get_detail_card_type_func(p_card_type_id INT)
RETURNS SETOF card_type
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM card_type
    WHERE card_type_id = p_card_type_id;
END;
$$;
