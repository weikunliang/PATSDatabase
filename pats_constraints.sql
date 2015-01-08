-- CONSTRAINTS FOR PATS DATABASE
--
-- by Weikun Liang & Mallory Hayase
--
--


-- Pet
ALTER TABLE pets ADD CONSTRAINT animal_fkey FOREIGN KEY (animal_id) REFERENCES animals (id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE pets ADD CONSTRAINT owner_fkey FOREIGN KEY (owner_id) REFERENCES owners (id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Visit
ALTER TABLE visits ADD CONSTRAINT pet_fkey FOREIGN KEY (pet_id) REFERENCES pets (id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AnimalMedicine
ALTER TABLE animal_medicines ADD CONSTRAINT animal_fkey FOREIGN KEY (animal_id) REFERENCES animals (id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE animal_medicines ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- VisitMedicine
ALTER TABLE visit_medicines ADD CONSTRAINT visit_fkey FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE visit_medicines ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Treatment
ALTER TABLE treatments ADD CONSTRAINT visit_fkey FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE treatments ADD CONSTRAINT procedure_fkey FOREIGN KEY (procedure_id) REFERENCES procedures (id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- MedicineCost
ALTER TABLE medicine_costs ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE ON UPDATE CASCADE;

-- ProcedureCost
ALTER TABLE procedure_costs ADD CONSTRAINT procedure_fkey FOREIGN KEY (procedure_id) REFERENCES procedures (id) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE owners ADD CONSTRAINT validate_phone CHECK (phone ~* '^[0-9]{10}$');

ALTER TABLE owners ADD CONSTRAINT validate_email CHECK (email ~* '^[A-Za-z0-9.''_%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$');