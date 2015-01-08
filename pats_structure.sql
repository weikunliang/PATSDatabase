-- TABLE STRUCTURE FOR PATS DATABASE
--
-- by Weikun Liang & Mallory Hayase
--
--
CREATE TABLE owners (
	id SERIAL PRIMARY KEY,
	first_name character varying(255) NOT NULL,
	last_name character varying(255) NOT NULL,
	street character varying(255) NOT NULL,
	city character varying(255) NOT NULL,
	state character varying(255) DEFAULT 'PA', 
	zip integer NOT NULL,
	phone character varying(255),
	email character varying(255),
	active boolean DEFAULT true
);

CREATE TABLE pets (
	id SERIAL PRIMARY KEY,
	name character varying(255) NOT NULL,
	animal_id integer NOT NULL,
	owner_id integer NOT NULL,
	female boolean DEFAULT true,
	date_of_birth date,
	active boolean DEFAULT true
);

CREATE TABLE visits (
	id SERIAL PRIMARY KEY, 
	pet_id integer NOT NULL,
	date date NOT NULL,
	weight integer,
	overnight_stay boolean DEFAULT false, 
	total_charge integer DEFAULT 0
);

CREATE TABLE animals (
	id SERIAL PRIMARY KEY,
	name character varying(255) NOT NULL,
	active boolean DEFAULT true
);

CREATE TABLE medicines (
	id SERIAL PRIMARY KEY,
	name character varying(255) NOT NULL,
	description text NOT NULL,
	stock_amount integer NOT NULL,
	method character varying(255) NOT NULL,
	unit character varying(255) NOT NULL,
	vaccine boolean DEFAULT false,
	CONSTRAINT medicines_check_method CHECK (((method)::text ~*'^(oral|intravenous|injection)$'::text))
);

CREATE TABLE medicine_costs (
	id SERIAL PRIMARY KEY,
	medicine_id integer NOT NULL,
	cost_per_unit integer NOT NULL,
	start_date date NOT NULL,
	end_date date
);

CREATE TABLE animal_medicines (
	id SERIAL PRIMARY KEY,
	animal_id integer NOT NULL,
	medicine_id integer NOT NULL,
	recommended_num_of_units integer
);

CREATE TABLE visit_medicines (
	id SERIAL PRIMARY KEY,
	visit_id integer NOT NULL,
	medicine_id integer NOT NULL,
	units_given integer NOT NULL,
	discount float DEFAULT 0.00, 
	CONSTRAINT visit_medicines_check_discount CHECK ((discount <= 1.00))
);

CREATE TABLE procedures (
	id SERIAL PRIMARY KEY,
	name character varying(255) NOT NULL,
	description text,
	length_of_time integer NOT NULL,
	active boolean DEFAULT true
);

CREATE TABLE treatments (
	id SERIAL PRIMARY KEY,
	visit_id integer NOT NULL,
	procedure_id integer NOT NULL,
	successful boolean,
	discount float DEFAULT 0.00
);

CREATE TABLE procedure_costs (
	id SERIAL PRIMARY KEY,
	procedure_id integer NOT NULL,
	cost integer NOT NULL, 
	start_date date NOT NULL, 
	end_date date
);

CREATE TABLE notes (
	id SERIAL PRIMARY KEY,
	notable_type character varying(255) NOT NULL,
	notable_id integer NOT NULL,
	title character varying(255) NOT NULL,
	content text NOT NULL,
	user_id integer NOT NULL,
	date date NOT NULL
);

CREATE TABLE users (
	id SERIAL PRIMARY KEY,
	first_name character varying(255) NOT NULL,
	last_name character varying(255) NOT NULL,
	role character varying(255) NOT NULL,
	username character varying(255) NOT NULL UNIQUE,
	password_digest character varying(255) NOT NULL,
	active boolean DEFAULT true
);

