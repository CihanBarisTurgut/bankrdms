CREATE OR REPLACE FUNCTION get_detail_customer_func(p_tc_no CHAR)
RETURNS SETOF customer
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM customer
    WHERE tc_no = p_tc_no;
END;
$$;
