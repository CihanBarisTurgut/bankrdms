CREATE OR REPLACE PROCEDURE create_transaction_type_proc(
    p_type_name VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM transaction_type WHERE type_name = p_type_name) THEN
        RAISE EXCEPTION 'Bu işlem tipi adı zaten mevcut (Ad: %)', p_type_name;
    END IF;

    INSERT INTO transaction_type(type_name)
    VALUES(p_type_name);

    RAISE NOTICE 'İşlem tipi başarıyla oluşturuldu (Ad: %)', p_type_name;
END;
$$;