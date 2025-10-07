CREATE OR REPLACE PROCEDURE delete_transaction_type_proc(
    p_transaction_type_id INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM transaction_type WHERE transaction_type_id = p_transaction_type_id) THEN
        RAISE EXCEPTION 'İşlem tipi bulunamadı (ID: %)', p_transaction_type_id;
    END IF;
	
	-- soft delete değil çünkü gereksiz
    DELETE FROM transaction_type
    WHERE transaction_type_id = p_transaction_type_id;

    RAISE NOTICE 'İşlem tipi başarıyla silindi (ID: %)', p_transaction_type_id;
END;
$$;
