CREATE OR REPLACE FUNCTION get_list_customer_func()
RETURNS SETOF customer
LANGUAGE plpgsql
AS $$
BEGIN

	RETURN QUERY SELECT*FROM customer;

END;
$$;