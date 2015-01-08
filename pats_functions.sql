-- FUNCTIONS AND TRIGGERS FOR PATS DATABASE
--
-- by Mallory Hayase and Weikun Liang
--
--

--------------------------------------------------------
--              Calculate total costs               ----
--------------------------------------------------------
-- calculate_total_costs
-- (associated with two triggers: update_total_costs_for_medicines_changes & update_total_costs_for_treatments_changes)

CREATE OR REPLACE FUNCTION calculate_total_costs() RETURNS TRIGGER AS $$
    DECLARE
        visit  INTEGER;
        medicine INTEGER;
        med_cost INTEGER;
        procedure_cost INTEGER;
        total_cost INTEGER;
        med_discount FLOAT;
        procedure INTEGER;
        procedure_discount FLOAT;
        med_units INTEGER;
        row_data RECORD;
    BEGIN
        total_cost = 0;
        visit = NEW.visit_id;
        FOR row_data IN (SELECT DISTINCT * FROM visit_medicines WHERE visit_id = visit)
        LOOP
            medicine = row_data.medicine_id;
            med_cost = (SELECT cost_per_unit 
                       FROM medicine_costs mc 
                       JOIN medicines m on mc.medicine_id = m.id 
                       WHERE mc.end_date IS NULL AND mc.medicine_id = medicine);
            med_discount = (SELECT discount FROM visit_medicines 
                            WHERE medicine_id = medicine AND id = row_data.id);
            med_units = (SELECT units_given from visit_medicines 
                            WHERE id = row_data.id);
            total_cost = total_cost + ((1-med_discount) * (med_units*med_cost));
        END LOOP;

        --- Procedure Costs ---
        FOR row_data IN (SELECT DISTINCT * FROM treatments WHERE visit_id = visit)
        LOOP
            procedure = row_data.procedure_id;
            procedure_cost = (SELECT DISTINCT cost 
                             FROM procedure_costs pc 
                             JOIN procedures p ON pc.procedure_id = p.id 
                             JOIN treatments t ON t.procedure_id = p.id
                             WHERE pc.end_date IS NULL AND pc.procedure_id = procedure);
            procedure_discount = (SELECT discount FROM treatments 
                                    WHERE procedure_id = procedure AND id = row_data.id);
            total_cost = total_cost + ((1-procedure_discount) * procedure_cost);
        END LOOP;
        UPDATE visits SET total_charge = total_cost WHERE id = visit;
        RETURN NULL;
    END;
$$ LANGUAGE plpgsql;

--** TRIGGERS **--
CREATE TRIGGER update_total_costs_for_medicines_changes
AFTER INSERT OR UPDATE ON visit_medicines FOR EACH ROW
EXECUTE PROCEDURE calculate_total_costs();

CREATE TRIGGER update_total_costs_for_treatments_changes
AFTER INSERT OR UPDATE ON treatments FOR EACH ROW
EXECUTE PROCEDURE calculate_total_costs();

------------------------------------------------------------
--          Calculate overnight stay                    ----
------------------------------------------------------------

CREATE OR REPLACE FUNCTION calculate_overnight_stay() RETURNS TRIGGER AS $$
    DECLARE
        total_time integer;
        last_treatment integer;
        v_id integer;
        r RECORD;
    BEGIN
        total_time = 0;
        last_treatment = (SELECT currval(pg_get_serial_sequence('treatments', 'id')));
        v_id = (select visit_id from treatments where id = last_treatment);
        FOR r IN SELECT * from treatments where visit_id = v_id
        LOOP
            total_time = total_time + (select length_of_time from procedures where id = r.procedure_id);
        END LOOP;
        IF total_time > 720 THEN 
            UPDATE visits SET overnight_stay = true where id = v_id;
        ELSE
            UPDATE visits SET overnight_stay = false where id = v_id;
        END IF;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

--** TRIGGER **--
CREATE TRIGGER update_overnight_stay_flag
AFTER INSERT ON treatments
EXECUTE PROCEDURE calculate_overnight_stay();


--------------------------------------------------------
--          Set end date for medicine  costs        ----
--------------------------------------------------------

CREATE OR REPLACE FUNCTION set_end_date_for_medicine_costs() RETURNS TRIGGER AS $$
    BEGIN

    UPDATE medicine_costs SET end_date = current_date WHERE medicine_id = NEW.medicine_id AND end_date IS NULL;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS set_end_date_for_previous_medicine_cost ON medicine_costs;
CREATE TRIGGER set_end_date_for_previous_medicine_cost
BEFORE INSERT ON medicine_costs
FOR EACH ROW
EXECUTE PROCEDURE set_end_date_for_medicine_costs();

------------------------------------------------------------
--          Set end date for procedure costs            ----
------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_end_date_for_procedure_cost() RETURNS TRIGGER AS $$
    BEGIN

    UPDATE procedure_costs SET end_date = current_date WHERE procedure_id = NEW.procedure_id AND end_date IS NULL;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

CREATE TRIGGER set_end_date_for_previous_procedure_cost
BEFORE INSERT ON procedure_costs
FOR EACH ROW
EXECUTE PROCEDURE set_end_date_for_procedure_cost();



------------------------------------------------------------
--          Update Stock Amount                         ----
------------------------------------------------------------

CREATE OR REPLACE FUNCTION decrease_stock_amount_after_dosage() RETURNS TRIGGER AS $$
    DECLARE
        last_vm INTEGER;
        units_given INTEGER;
        medicine_given INTEGER;
        old_stock_amount INTEGER;
        new_stock_amount INTEGER;
    BEGIN
        last_vm = (SELECT currval(pg_get_serial_sequence('visit_medicines', 'id')));
        units_given = (SELECT vm.units_given FROM visit_medicines vm WHERE id = last_vm);
        medicine_given = (SELECT medicine_id FROM visit_medicines WHERE id = last_vm);
        old_stock_amount = (SELECT stock_amount FROM medicines WHERE id = medicine_given);
        new_stock_amount = old_stock_amount - units_given;
        UPDATE medicines SET stock_amount = new_stock_amount WHERE id = medicine_given;
        RETURN NULL;
    END
    $$ 
LANGUAGE plpgsql;

--** TRIGGER **--
CREATE TRIGGER update_medicine_stock_amount
AFTER INSERT OR UPDATE ON visit_medicines
EXECUTE PROCEDURE decrease_stock_amount_after_dosage();



----------------------------------------------------------------
--          Verify Medicine In Stock                        ----
----------------------------------------------------------------

CREATE OR REPLACE FUNCTION verify_that_medicine_requested_in_stock(medicine_id INTEGER, units_needed INTEGER) 
    RETURNS BOOLEAN 
    AS $$
    DECLARE
        current_stock INTEGER;
    BEGIN
        --Alert user that units_needed is likely not a valid amount--
        IF units_needed < 0 THEN 
            RAISE NOTICE 'Units of medicine needed (%) is a negative number; This is not a valid amount.', units_needed;
            RETURN FALSE;
        END IF;

        current_stock = (SELECT stock_amount FROM medicines WHERE id = medicine_id);
        
        --If ID given does not belong to any medicines, raise notice--
        IF current_stock IS NULL THEN
            RAISE NOTICE 'Medicine ID provided (%) does not belong to any medicines in stock.', medicine_id;
            RETURN FALSE;
        END IF;
        
        IF current_stock < units_needed THEN
            RETURN FALSE;
        ELSE 
            RETURN TRUE;
        END IF;
    END
    $$
LANGUAGE plpgsql;


----------------------------------------------------------------
--          Verify Medicine Appropriate for Pet             ----
----------------------------------------------------------------

CREATE OR REPLACE FUNCTION verify_that_medicine_is_appropriate_for_pet(medicine_id INTEGER, pet_id INTEGER) 
    RETURNS BOOLEAN 
    AS $$
    DECLARE
        animal INTEGER;
        med_id INTEGER;
    BEGIN
        --If medicine ID given does not belong to any medicines, raise notice--
        IF medicine_id NOT IN (SELECT id FROM medicines) THEN
            RAISE NOTICE 'Medicine ID provided (%) does not belong to any medicines in stock.', medicine_id;
            RETURN NULL;
        END IF;

        --If pet ID given does not belong to any pets, raise notice--
        IF pet_id NOT IN (SELECT id FROM pets) THEN
            RAISE NOTICE 'Pet ID provided (%) does not belong to any pets in stock.', pet_id;
            RETURN NULL;
        END IF;

        animal = (SELECT animal_id FROM pets where id = pet_id);  
        med_id = medicine_id;
        IF animal NOT IN  (SELECT animal_id FROM animal_medicines am WHERE am.medicine_id = med_id) THEN
            RETURN FALSE;
        ELSE
            RETURN TRUE;
        END IF;
    END
    $$ 
LANGUAGE plpgsql;
