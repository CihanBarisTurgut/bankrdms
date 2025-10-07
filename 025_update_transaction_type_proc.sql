CREATE OR REPLACE PROCEDURE update_transaction_type_proc(
    p_transaction_type_id INT,
    p_type_name VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_current_type_name VARCHAR;
BEGIN
    SELECT type_name INTO p_current_type_name
    FROM transaction_type
    WHERE transaction_type_id = p_transaction_type_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'İşlem tipi bulunamadı (ID: %)', p_transaction_type_id;
    END IF;

    IF p_type_name IS NOT NULL AND p_type_name <> p_current_type_name THEN
        IF EXISTS (SELECT 1 FROM transaction_type WHERE type_name = p_type_name) THEN
            RAISE EXCEPTION 'Bu işlem tipi adı zaten mevcut (Ad: %)', p_type_name;
        END IF;
    END IF;


    UPDATE transaction_type
    SET type_name = COALESCE(p_type_name, type_name)
    WHERE transaction_type_id = p_transaction_type_id;

    RAISE NOTICE 'İşlem tipi başarıyla güncellendi (ID: %)', p_transaction_type_id;
END;
$$;
