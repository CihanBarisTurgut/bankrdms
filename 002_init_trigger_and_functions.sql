-- 1- customer tablosu için INSERT sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_customer_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(table_name, operation_type, record_id, new_data)
    VALUES('customer', 'INSERT', NEW.customer_id, json_build_object('customer_name', NEW.customer_name, 'tc_no', NEW.tc_no));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2- account tablosu için INSERT sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_account_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(table_name, operation_type, record_id, new_data)
    VALUES('account', 'INSERT', NEW.account_id, json_build_object('iban', NEW.iban, 'account_name', NEW.account_name));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3- account tablosu için UPDATE sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_account_update_func() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.iban <> NEW.iban OR OLD.account_name <> NEW.account_name OR OLD.status <> NEW.status  THEN
        INSERT INTO audit_log(table_name, operation_type, record_id, old_data, new_data)
        VALUES('account', 'UPDATE', NEW.account_id,
        json_build_object('iban', OLD.iban,'account_name',OLD.account_name, 'status',OLD.status),
        json_build_object('iban', NEW.iban,'account_name',NEW.account_name, 'status',NEW.status));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4- card_type tablosu için INSERT sonrası tetikleyici fonksiyonu (Tekilleştirildi)
CREATE OR REPLACE FUNCTION after_card_type_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(table_name, operation_type, record_id, new_data)
    VALUES ('card_type', 'INSERT', NEW.card_type_id, json_build_object('type_name', NEW.type_name, 'description', NEW.description));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5- transaction_type tablosu için INSERT sonrası tetikleyici fonksiyonu (Tekilleştirildi)
CREATE OR REPLACE FUNCTION after_transaction_type_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(table_name, operation_type, record_id, new_data)
    VALUES ('transaction_type', 'INSERT', NEW.transaction_type_id, json_build_object('type_name', NEW.type_name));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6- card tablosu için INSERT sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_card_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_data)
    VALUES ('card', 'INSERT', NEW.card_id, json_build_object('card_number', NEW.card_number, 'card_type_id', NEW.card_type_id));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7- card tablosu için UPDATE sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_card_update_func() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.current_debt <> NEW.current_debt OR OLD.status <> NEW.status OR OLD.limit_amount <> NEW.limit_amount OR (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL) THEN
        INSERT INTO audit_log (table_name, operation_type, record_id, old_data, new_data)
        VALUES ('card', 'UPDATE', NEW.card_id,
                json_build_object('current_debt', OLD.current_debt, 'status', OLD.status, 'limit_amount', OLD.limit_amount, 'deleted_at', OLD.deleted_at),
                json_build_object('current_debt', NEW.current_debt, 'status', NEW.status, 'limit_amount', NEW.limit_amount, 'deleted_at', NEW.deleted_at));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 8- transaction tablosu için INSERT sonrası tetikleyici fonksiyonu
CREATE OR REPLACE FUNCTION after_transaction_insert_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation_type, record_id, new_data)
    VALUES ('transaction', 'INSERT', NEW.transaction_id, json_build_object('card_id', NEW.card_id, 'amount', NEW.amount, 'description', NEW.description));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9- yeni bir hesap kartı eklendiğinde mevcut aktif hesap kartı varsa yeni kartın pasif hale getirilmesi
CREATE OR REPLACE FUNCTION before_card_insert_func() RETURNS TRIGGER AS $$
DECLARE
	p_account_card_type_id INT;
	active_card_exists BOOLEAN;
BEGIN
	SELECT card_type_id INTO p_account_card_type_id FROM card_type where type_name='ACCOUNT';

	IF NEW.card_type_id=p_account_card_type_id THEN
		SELECT EXISTS(
			SELECT 1
			FROM card
			WHERE customer_id=NEW.customer_id
				AND card_type_id=p_account_card_type_id
				AND status='ACTIVE'
		) INTO active_card_exists;

		IF active_card_exists THEN
			NEW.status='INACTIVE';
		END IF;
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 10- customer tablosundan müşteri silinmesi
CREATE OR REPLACE FUNCTION after_customer_soft_delete_func()
RETURNS TRIGGER AS $$
BEGIN
    -- deleted_at NULL iken yeni değeri dolu ise bu soft delete demektir
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        INSERT INTO audit_log(table_name, operation_type, record_id, old_data)
        VALUES(
            'customer',
            'DELETE',
            OLD.customer_id,
            json_build_object('customer_name', OLD.customer_name, 'tc_no', OLD.tc_no)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--11- account tablosundan hesap silinmesi
CREATE OR REPLACE FUNCTION after_account_soft_delete_func()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        INSERT INTO audit_log(table_name, operation_type, record_id, old_data)
        VALUES(
            'account',
            'DELETE',
            OLD.account_id,
            json_build_object('iban', OLD.iban, 'account_name', OLD.account_name)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--12- customer tablosunda müşteri güncellenmesi
CREATE OR REPLACE FUNCTION after_customer_update_func()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.customer_name <> NEW.customer_name
       OR OLD.tc_no <> NEW.tc_no
       OR OLD.birth_date <> NEW.birth_date
       OR OLD.birth_place <> NEW.birth_place
       OR OLD.risk_limit <> NEW.risk_limit THEN

        INSERT INTO audit_log(
            table_name,
            operation_type,
            record_id,
            old_data,
            new_data
        )
        VALUES(
            'customer',
            'UPDATE',
            NEW.customer_id,
            json_build_object(
                'customer_name', OLD.customer_name,
                'tc_no', OLD.tc_no,
                'birth_date', OLD.birth_date,
                'birth_place', OLD.birth_place,
                'risk_limit', OLD.risk_limit
            ),
            json_build_object(
                'customer_name', NEW.customer_name,
                'tc_no', NEW.tc_no,
                'birth_date', NEW.birth_date,
                'birth_place', NEW.birth_place,
                'risk_limit', NEW.risk_limit
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--13- card type tablosuna UPDATE yapıldıktan sonra
CREATE OR REPLACE FUNCTION after_card_type_update_func()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.type_name <> NEW.type_name OR OLD.description <> NEW.description THEN
        INSERT INTO audit_log(
            table_name,
            operation_type,
            record_id,
            old_data,
            new_data
        )
        VALUES(
            'card_type',
            'UPDATE',
            NEW.card_type_id,
            json_build_object(
                'type_name', OLD.type_name,
                'description', OLD.description
            ),
            json_build_object(
                'type_name', NEW.type_name,
                'description', NEW.description
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--14- card type tablosuna DELETE yapıldıktan sonra
CREATE OR REPLACE FUNCTION after_card_type_delete_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(
        table_name,
        operation_type,
        record_id,
        old_data
    )
    VALUES(
        'card_type',
        'DELETE',
        OLD.card_type_id,
        json_build_object(
            'type_name', OLD.type_name,
            'description', OLD.description
        )
    );

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- 15-  bir hesap kartı güncellenip aktif yapılırsa mevcutta da aktif hesap kartı varsa mevcuttaki kartın pasif hale getirilmesi
CREATE OR REPLACE FUNCTION before_card_update_func() RETURNS TRIGGER AS $$
DECLARE
    p_account_card_type_id INT;
BEGIN
    SELECT card_type_id INTO p_account_card_type_id FROM card_type WHERE type_name = 'ACCOUNT';

    IF NEW.card_type_id = p_account_card_type_id AND NEW.status = 'ACTIVE' THEN
        UPDATE card
        SET status = 'INACTIVE'
        WHERE customer_id = NEW.customer_id
          AND card_type_id = p_account_card_type_id
          AND status = 'ACTIVE'
          AND card_id != NEW.card_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--16 card tablosunda DELETE yapıldıktan sonra log kaydı
CREATE OR REPLACE FUNCTION after_card_soft_delete_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(
        table_name,
        operation_type,
        record_id,
        old_data
    )
    VALUES(
        'card',
        'DELETE',
        OLD.card_id,
        json_build_object(
            'customer_id', OLD.customer_id,
            'account_id', OLD.account_id,
            'card_type_id', OLD.card_type_id,
            'card_number', OLD.card_number,
            'expiry_month', OLD.expiry_month,
            'expiry_year', OLD.expiry_year,
            'ccv', OLD.ccv,
            'limit_amount', OLD.limit_amount,
            'current_debt', OLD.current_debt,
            'balance', OLD.balance,
            'status', OLD.status
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--17 transaction type UPDATE sonrası log
CREATE OR REPLACE FUNCTION after_transaction_type_update_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(
        table_name,
        operation_type,
        record_id,
        old_data,
        new_data
    )
    VALUES(
        'transaction_type',
        'UPDATE',
        NEW.transaction_type_id,
        json_build_object(
            'old_type_name', OLD.type_name
        ),
        json_build_object(
            'new_type_name', NEW.type_name
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--18 transaction type DELETE sonrası log
CREATE OR REPLACE FUNCTION after_transaction_type_delete_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log(
        table_name,
        operation_type,
        record_id,
        old_data
    )
    VALUES(
        'transaction_type',
        'DELETE',
        OLD.transaction_type_id,
        json_build_object(
            'type_name', OLD.type_name
        )
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

--19 çekilecek para bakiyeden büyükse engelle
CREATE OR REPLACE FUNCTION check_card_balance_on_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Eğer güncellenen satır 'ACCOUNT' tipi bir karta aitse VE
    -- balance sütununun değeri değişiyorsa bu kontrolü yap.
    IF NEW.card_type_id = (SELECT card_type_id FROM card_type WHERE type_name = 'ACCOUNT') 
    AND OLD.balance IS DISTINCT FROM NEW.balance THEN

        -- Yeni bakiye değeri eksiye düşüyorsa hata fırlat ve işlemi iptal et.
        IF NEW.balance < 0 THEN
            RAISE EXCEPTION 'Hesap bakiyesi eksiye düşemez. İşlem iptal edildi.';
        END IF;

    END IF;

    -- Kontrolden geçtiyse, işlemi devam ettir.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_check_card_balance_update
BEFORE UPDATE ON card
FOR EACH ROW
EXECUTE FUNCTION check_card_balance_on_update();

CREATE OR REPLACE TRIGGER after_transaction_type_update
AFTER UPDATE ON transaction_type
FOR EACH ROW
EXECUTE FUNCTION after_transaction_type_update_func();

CREATE OR REPLACE TRIGGER after_transaction_type_delete
AFTER DELETE ON transaction_type
FOR EACH ROW
EXECUTE FUNCTION after_transaction_type_delete_func();


CREATE TRIGGER after_card_soft_delete
AFTER UPDATE ON card
FOR EACH ROW
EXECUTE FUNCTION after_card_soft_delete_func();

CREATE OR REPLACE TRIGGER before_card_update
BEFORE UPDATE ON card
FOR EACH ROW
EXECUTE FUNCTION before_card_update_func();

CREATE TRIGGER after_account_soft_delete
AFTER UPDATE ON account
FOR EACH ROW
EXECUTE FUNCTION after_account_soft_delete_func();

CREATE TRIGGER after_customer_soft_delete
AFTER UPDATE ON customer
FOR EACH ROW
EXECUTE FUNCTION after_customer_soft_delete_func();

CREATE OR REPLACE TRIGGER after_customer_insert
AFTER INSERT ON customer
FOR EACH ROW EXECUTE PROCEDURE after_customer_insert_func();

CREATE TRIGGER after_customer_update
AFTER UPDATE ON customer
FOR EACH ROW
EXECUTE FUNCTION after_customer_update_func();

CREATE OR REPLACE TRIGGER after_account_insert
AFTER INSERT ON account
FOR EACH ROW EXECUTE PROCEDURE after_account_insert_func();

CREATE OR REPLACE TRIGGER after_account_update
AFTER UPDATE ON account
FOR EACH ROW EXECUTE PROCEDURE after_account_update_func();

CREATE OR REPLACE TRIGGER after_card_type_insert
AFTER INSERT ON card_type
FOR EACH ROW EXECUTE PROCEDURE after_card_type_insert_func();

CREATE OR REPLACE TRIGGER after_transaction_type_insert
AFTER INSERT ON transaction_type
FOR EACH ROW EXECUTE PROCEDURE after_transaction_type_insert_func();

CREATE OR REPLACE TRIGGER after_card_insert
AFTER INSERT ON card
FOR EACH ROW EXECUTE PROCEDURE after_card_insert_func();

CREATE OR REPLACE TRIGGER after_card_update
AFTER UPDATE ON card
FOR EACH ROW EXECUTE PROCEDURE after_card_update_func();

CREATE OR REPLACE TRIGGER after_transaction_insert
AFTER INSERT ON transaction
FOR EACH ROW EXECUTE PROCEDURE after_transaction_insert_func();

CREATE OR REPLACE TRIGGER before_card_insert
BEFORE INSERT ON card
FOR EACH ROW EXECUTE PROCEDURE before_card_insert_func();

CREATE TRIGGER after_card_type_update
AFTER UPDATE ON card_type
FOR EACH ROW
EXECUTE FUNCTION after_card_type_update_func();

CREATE TRIGGER after_card_type_delete
AFTER DELETE ON card_type
FOR EACH ROW
EXECUTE FUNCTION after_card_type_delete_func();