--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: calculate_overnight_stay(); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION calculate_overnight_stay() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
    $$;


ALTER FUNCTION public.calculate_overnight_stay() OWNER TO weikunliang;

--
-- Name: calculate_total_costs(); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION calculate_total_costs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.calculate_total_costs() OWNER TO weikunliang;

--
-- Name: decrease_stock_amount_after_dosage(); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION decrease_stock_amount_after_dosage() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
    $$;


ALTER FUNCTION public.decrease_stock_amount_after_dosage() OWNER TO weikunliang;

--
-- Name: set_end_date_for_medicine_costs(); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION set_end_date_for_medicine_costs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN

    UPDATE medicine_costs SET end_date = current_date WHERE medicine_id = NEW.medicine_id AND end_date IS NULL;
      RETURN NEW;
    END;
    $$;


ALTER FUNCTION public.set_end_date_for_medicine_costs() OWNER TO weikunliang;

--
-- Name: set_end_date_for_procedure_cost(); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION set_end_date_for_procedure_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN

    UPDATE procedure_costs SET end_date = current_date WHERE procedure_id = NEW.procedure_id AND end_date IS NULL;
      RETURN NEW;
    END;
    $$;


ALTER FUNCTION public.set_end_date_for_procedure_cost() OWNER TO weikunliang;

--
-- Name: verify_that_medicine_is_appropriate_for_pet(integer, integer); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION verify_that_medicine_is_appropriate_for_pet(medicine_id integer, pet_id integer) RETURNS boolean
    LANGUAGE plpgsql
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
    $$;


ALTER FUNCTION public.verify_that_medicine_is_appropriate_for_pet(medicine_id integer, pet_id integer) OWNER TO weikunliang;

--
-- Name: verify_that_medicine_requested_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: weikunliang
--

CREATE FUNCTION verify_that_medicine_requested_in_stock(medicine_id integer, units_needed integer) RETURNS boolean
    LANGUAGE plpgsql
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
    $$;


ALTER FUNCTION public.verify_that_medicine_requested_in_stock(medicine_id integer, units_needed integer) OWNER TO weikunliang;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: animal_medicines; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE animal_medicines (
    id integer NOT NULL,
    animal_id integer NOT NULL,
    medicine_id integer NOT NULL,
    recommended_num_of_units integer
);


ALTER TABLE public.animal_medicines OWNER TO weikunliang;

--
-- Name: animal_medicines_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE animal_medicines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.animal_medicines_id_seq OWNER TO weikunliang;

--
-- Name: animal_medicines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE animal_medicines_id_seq OWNED BY animal_medicines.id;


--
-- Name: animals; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE animals (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE public.animals OWNER TO weikunliang;

--
-- Name: animals_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE animals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.animals_id_seq OWNER TO weikunliang;

--
-- Name: animals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE animals_id_seq OWNED BY animals.id;


--
-- Name: medicine_costs; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE medicine_costs (
    id integer NOT NULL,
    medicine_id integer NOT NULL,
    cost_per_unit integer NOT NULL,
    start_date date NOT NULL,
    end_date date
);


ALTER TABLE public.medicine_costs OWNER TO weikunliang;

--
-- Name: medicine_costs_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE medicine_costs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.medicine_costs_id_seq OWNER TO weikunliang;

--
-- Name: medicine_costs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE medicine_costs_id_seq OWNED BY medicine_costs.id;


--
-- Name: medicines; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE medicines (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text NOT NULL,
    stock_amount integer NOT NULL,
    method character varying(255) NOT NULL,
    unit character varying(255) NOT NULL,
    vaccine boolean DEFAULT false,
    CONSTRAINT medicines_check_method CHECK (((method)::text ~* '^(oral|intravenous|injection)$'::text))
);


ALTER TABLE public.medicines OWNER TO weikunliang;

--
-- Name: medicine_views; Type: VIEW; Schema: public; Owner: weikunliang
--

CREATE VIEW medicine_views AS
 SELECT m.id AS "medicine id",
    m.name AS "medicine name",
    m.description,
    m.stock_amount,
    m.unit,
    m.vaccine,
    a.id AS "animal id",
    a.name AS "animal name",
    a.active AS "animal active",
    am.recommended_num_of_units,
    mc.cost_per_unit AS "current cost",
    mc.start_date
   FROM (((medicines m
     JOIN animal_medicines am ON ((m.id = am.medicine_id)))
     JOIN animals a ON ((am.animal_id = a.id)))
     JOIN medicine_costs mc ON ((mc.medicine_id = m.id)))
  WHERE (mc.end_date IS NULL);


ALTER TABLE public.medicine_views OWNER TO weikunliang;

--
-- Name: medicines_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE medicines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.medicines_id_seq OWNER TO weikunliang;

--
-- Name: medicines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE medicines_id_seq OWNED BY medicines.id;


--
-- Name: notes; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE notes (
    id integer NOT NULL,
    notable_type character varying(255) NOT NULL,
    notable_id integer NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    user_id integer NOT NULL,
    date date NOT NULL
);


ALTER TABLE public.notes OWNER TO weikunliang;

--
-- Name: notes_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notes_id_seq OWNER TO weikunliang;

--
-- Name: notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE notes_id_seq OWNED BY notes.id;


--
-- Name: owners; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE owners (
    id integer NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    street character varying(255) NOT NULL,
    city character varying(255) NOT NULL,
    state character varying(255) DEFAULT 'PA'::character varying,
    zip integer NOT NULL,
    phone character varying(255),
    email character varying(255),
    active boolean DEFAULT true,
    CONSTRAINT validate_email CHECK (((email)::text ~* '^[A-Za-z0-9.''_%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'::text)),
    CONSTRAINT validate_phone CHECK (((phone)::text ~* '^[0-9]{10}$'::text))
);


ALTER TABLE public.owners OWNER TO weikunliang;

--
-- Name: owners_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE owners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.owners_id_seq OWNER TO weikunliang;

--
-- Name: owners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE owners_id_seq OWNED BY owners.id;


--
-- Name: pets; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE pets (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    animal_id integer NOT NULL,
    owner_id integer NOT NULL,
    female boolean DEFAULT true,
    date_of_birth date,
    active boolean DEFAULT true
);


ALTER TABLE public.pets OWNER TO weikunliang;

--
-- Name: visits; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE visits (
    id integer NOT NULL,
    pet_id integer NOT NULL,
    date date NOT NULL,
    weight integer,
    overnight_stay boolean DEFAULT false,
    total_charge integer DEFAULT 0
);


ALTER TABLE public.visits OWNER TO weikunliang;

--
-- Name: owners_view; Type: VIEW; Schema: public; Owner: weikunliang
--

CREATE VIEW owners_view AS
 SELECT o.id AS "owner id",
    o.first_name,
    o.last_name,
    o.street,
    o.city,
    o.state,
    o.zip,
    o.phone,
    o.email,
    o.active AS "owner active",
    p.id AS "pet id",
    p.name,
    a.name AS "animal name",
    p.female,
    p.date_of_birth,
    p.active AS "pet active",
    v.id AS "visit id",
    v.date,
    v.weight,
    v.overnight_stay,
    v.total_charge
   FROM (((owners o
     JOIN pets p ON ((o.id = p.owner_id)))
     JOIN visits v ON ((v.pet_id = p.id)))
     JOIN animals a ON ((a.id = p.animal_id)));


ALTER TABLE public.owners_view OWNER TO weikunliang;

--
-- Name: pets_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE pets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pets_id_seq OWNER TO weikunliang;

--
-- Name: pets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE pets_id_seq OWNED BY pets.id;


--
-- Name: procedure_costs; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE procedure_costs (
    id integer NOT NULL,
    procedure_id integer NOT NULL,
    cost integer NOT NULL,
    start_date date NOT NULL,
    end_date date
);


ALTER TABLE public.procedure_costs OWNER TO weikunliang;

--
-- Name: procedure_costs_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE procedure_costs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.procedure_costs_id_seq OWNER TO weikunliang;

--
-- Name: procedure_costs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE procedure_costs_id_seq OWNED BY procedure_costs.id;


--
-- Name: procedures; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE procedures (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    length_of_time integer NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE public.procedures OWNER TO weikunliang;

--
-- Name: procedures_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE procedures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.procedures_id_seq OWNER TO weikunliang;

--
-- Name: procedures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE procedures_id_seq OWNED BY procedures.id;


--
-- Name: treatments; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE treatments (
    id integer NOT NULL,
    visit_id integer NOT NULL,
    procedure_id integer NOT NULL,
    successful boolean,
    discount double precision DEFAULT 0.00
);


ALTER TABLE public.treatments OWNER TO weikunliang;

--
-- Name: treatments_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE treatments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.treatments_id_seq OWNER TO weikunliang;

--
-- Name: treatments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE treatments_id_seq OWNED BY treatments.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    role character varying(255) NOT NULL,
    username character varying(255) NOT NULL,
    password_digest character varying(255) NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE public.users OWNER TO weikunliang;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO weikunliang;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: visit_medicines; Type: TABLE; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE TABLE visit_medicines (
    id integer NOT NULL,
    visit_id integer NOT NULL,
    medicine_id integer NOT NULL,
    units_given integer NOT NULL,
    discount double precision DEFAULT 0.00,
    CONSTRAINT visit_medicines_check_discount CHECK ((discount <= (1.00)::double precision))
);


ALTER TABLE public.visit_medicines OWNER TO weikunliang;

--
-- Name: visit_medicines_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE visit_medicines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.visit_medicines_id_seq OWNER TO weikunliang;

--
-- Name: visit_medicines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE visit_medicines_id_seq OWNED BY visit_medicines.id;


--
-- Name: visits_id_seq; Type: SEQUENCE; Schema: public; Owner: weikunliang
--

CREATE SEQUENCE visits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.visits_id_seq OWNER TO weikunliang;

--
-- Name: visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: weikunliang
--

ALTER SEQUENCE visits_id_seq OWNED BY visits.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY animal_medicines ALTER COLUMN id SET DEFAULT nextval('animal_medicines_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY animals ALTER COLUMN id SET DEFAULT nextval('animals_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY medicine_costs ALTER COLUMN id SET DEFAULT nextval('medicine_costs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY medicines ALTER COLUMN id SET DEFAULT nextval('medicines_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY notes ALTER COLUMN id SET DEFAULT nextval('notes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY owners ALTER COLUMN id SET DEFAULT nextval('owners_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY pets ALTER COLUMN id SET DEFAULT nextval('pets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY procedure_costs ALTER COLUMN id SET DEFAULT nextval('procedure_costs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY procedures ALTER COLUMN id SET DEFAULT nextval('procedures_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY treatments ALTER COLUMN id SET DEFAULT nextval('treatments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY visit_medicines ALTER COLUMN id SET DEFAULT nextval('visit_medicines_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY visits ALTER COLUMN id SET DEFAULT nextval('visits_id_seq'::regclass);


--
-- Data for Name: animal_medicines; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY animal_medicines (id, animal_id, medicine_id, recommended_num_of_units) FROM stdin;
1	3	1	\N
2	1	2	\N
3	2	2	\N
4	3	2	\N
5	4	2	\N
6	5	2	\N
7	3	3	\N
8	2	4	\N
9	3	4	\N
10	2	5	\N
11	3	5	\N
12	1	6	\N
13	2	6	\N
14	3	6	\N
15	4	6	\N
16	5	6	\N
17	1	7	\N
18	3	8	\N
19	2	9	\N
20	3	9	\N
21	4	9	\N
22	5	9	\N
23	2	10	\N
\.


--
-- Name: animal_medicines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('animal_medicines_id_seq', 23, true);


--
-- Data for Name: animals; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY animals (id, name, active) FROM stdin;
1	Bird	t
2	Cat	t
3	Dog	t
4	Ferret	t
5	Rabbit	t
\.


--
-- Name: animals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('animals_id_seq', 5, true);


--
-- Data for Name: medicine_costs; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY medicine_costs (id, medicine_id, cost_per_unit, start_date, end_date) FROM stdin;
1	1	30	2012-06-09	\N
2	1	20	2012-02-09	2012-06-09
3	2	65	2012-08-09	\N
4	2	55	2012-04-09	2012-08-09
5	3	27	2012-09-09	\N
6	3	20	2012-02-09	2012-09-09
7	4	60	2012-08-09	\N
8	4	50	2012-04-09	2012-08-09
9	5	41	2012-07-09	\N
10	5	34	2012-04-09	2012-07-09
11	6	52	2012-07-09	\N
12	6	44	2012-04-09	2012-07-09
13	7	23	2012-08-09	\N
14	7	14	2012-03-09	2012-08-09
15	8	63	2012-06-09	\N
16	8	54	2012-02-09	2012-06-09
17	9	22	2012-06-09	\N
18	9	14	2012-04-09	2012-06-09
19	10	37	2012-09-09	\N
20	10	28	2012-03-09	2012-09-09
\.


--
-- Name: medicine_costs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('medicine_costs_id_seq', 20, true);


--
-- Data for Name: medicines; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY medicines (id, name, description, stock_amount, method, unit, vaccine) FROM stdin;
1	Carprofen	Used to relieve pain and inflammation in dogs. Annedotal reports of severe GI effects in cats.	3679	injection	mililiters	f
2	Deracoxib	Post operative pain management and osteoarthritis. Interest in use as adjunctive treatment to transitional cell carcinoma.	4172	oral	mililiters	f
4	Ketamine	Anesthetic and tranquilizer in cats, dogs, horses, and other animals	6434	intravenous	mililiters	f
6	Amoxicillin	Antibiotic indicated for susceptible gram positive and gram negative infections. Ineffective against species that produce beta-lactamase.	5066	injection	miligrams	f
7	Aureomycin	For use in birds for the treatment of bacterial pneumonia and bacterial enteritis.	5822	injection	miligrams	f
8	Pimobendan	Used to manage heart failure in dogs	4078	injection	miligrams	f
9	Ntroscanate	Anthelmintic used to treat Toxocara canis, Toxascaris leonina, Ancylostoma caninum, Uncinaria stenocephalia, Taenia, and Dipylidium caninum (roundworms, hookworms and tapeworms).	4673	intravenous	miligrams	f
10	Buprenorphine	Narcotic for pain relief in cats after surgery.	6783	injection	miligrams	f
3	Ivermectin	A broad-spectrum antiparasitic used in horses and dogs.	3209	intravenous	mililiters	f
5	Mirtazapine	Antiemetic and appetite stimulant in cats and dog	2027	injection	miligrams	f
\.


--
-- Name: medicines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('medicines_id_seq', 10, true);


--
-- Data for Name: notes; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY notes (id, notable_type, notable_id, title, content, user_id, date) FROM stdin;
\.


--
-- Name: notes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('notes_id_seq', 1, false);


--
-- Data for Name: owners; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY owners (id, first_name, last_name, street, city, state, zip, phone, email, active) FROM stdin;
1	Daniela	Williamson	380 Smith Motorway	Pittsburgh	PA	15213	0179533463	daniela.williamson@example.com	t
2	Cornelius	Beier	5416 Okuneva Vista	Penn Hills	PA	15235	4740661299	cornelius.beier@example.com	t
3	Keagan	Howe	70031 Sandy Haven	McCandless	PA	15090	1534627232	keagan.howe@example.com	t
4	Lamar	Conn	20015 Gaylord Ranch	Pittsburgh	PA	15213	0886212573	lamar.conn@example.com	t
5	Janice	Beahan	6853 Abdul Roads	Pittsburgh	PA	15237	6059088792	janice.beahan@example.com	t
6	Andy	Sauer	411 Hartmann Manor	Pittsburgh	PA	15212	0707809314	andy.sauer@example.com	t
7	Tom	Wuckert	47781 Amaya Turnpike	Penn Hills	PA	15235	2324754396	tom.wuckert@example.com	t
8	Ezekiel	Rowe	19413 Breitenberg Fords	Pittsburgh	PA	15237	8080152078	ezekiel.rowe@example.com	t
9	Sheridan	Roberts	7823 Arielle Rue	Shaler	PA	15209	2859936506	sheridan.roberts@example.com	t
10	Scot	Reilly	708 Ratke Loop	McCandless	PA	15090	4525830833	scot.reilly@example.com	t
11	Rolando	Murray	6321 Flo Lakes	Pittsburgh	PA	15213	5398656196	rolando.murray@example.com	t
12	Tyrel	Hyatt	56865 Genesis Falls	McCandless	PA	15090	8279733887	tyrel.hyatt@example.com	t
13	Dixie	Wiza	812 Kub Underpass	Pittsburgh	PA	15212	6136330977	dixie.wiza@example.com	t
14	Aliyah	Jacobson	9849 Pearlie Common	Pittsburgh	PA	15212	6564663896	aliyah.jacobson@example.com	t
15	Evelyn	Treutel	490 Schaefer Garden	Pittsburgh	PA	15212	1612387751	evelyn.treutel@example.com	t
16	Jedediah	Renner	86893 Langworth Prairie	Pittsburgh	PA	15212	9209643742	jedediah.renner@example.com	t
17	Allie	Ward	1146 Anna Radial	Shaler	PA	15209	0426414076	allie.ward@example.com	t
18	Jadon	DuBuque	5561 Lang Junction	McCandless	PA	15090	9315120339	jadon.dubuque@example.com	t
19	Elda	Feest	28520 Yessenia Terrace	Shaler	PA	15209	6276097575	elda.feest@example.com	t
20	Arely	Ritchie	15983 Scarlett Tunnel	McCandless	PA	15090	2364586626	arely.ritchie@example.com	t
21	Drew	Bechtelar	8060 Richie Walk	Shaler	PA	15209	6339451172	drew.bechtelar@example.com	t
22	Jayde	Ritchie	6108 Yadira Roads	McCandless	PA	15090	9709697491	jayde.ritchie@example.com	t
23	Augustine	Rowe	836 Gerson Gateway	McCandless	PA	15090	4071890860	augustine.rowe@example.com	t
24	Kaelyn	Gleason	4788 Carmella Wells	Pittsburgh	PA	15212	3005518977	kaelyn.gleason@example.com	t
25	Barton	Gislason	1819 Shields Street	Pittsburgh	PA	15213	7356841455	barton.gislason@example.com	t
26	Madisen	Bernhard	688 Heidenreich Station	Pittsburgh	PA	15212	4746347108	madisen.bernhard@example.com	t
27	Javonte	Treutel	605 Nannie Passage	Pittsburgh	PA	15212	3384310136	javonte.treutel@example.com	t
28	Maritza	Thiel	4202 Will Road	Penn Hills	PA	15235	9260708040	maritza.thiel@example.com	t
29	Chadrick	Ward	8015 Roberto Ways	Pittsburgh	PA	15212	1295507110	chadrick.ward@example.com	t
30	Zola	Jaskolski	36220 Alba Loaf	Pittsburgh	PA	15212	4896628655	zola.jaskolski@example.com	t
31	Faustino	Trantow	7423 Maria Crossroad	McCandless	PA	15090	1442308938	faustino.trantow@example.com	t
32	Coy	Marquardt	2706 Emmerich Lodge	Pittsburgh	PA	15213	8296549360	coy.marquardt@example.com	t
33	Cornell	McDermott	846 Breitenberg Tunnel	McCandless	PA	15090	3057114170	cornell.mcdermott@example.com	t
34	Braeden	Bechtelar	7204 Feil Road	McCandless	PA	15090	4897891379	braeden.bechtelar@example.com	t
35	Nick	Lind	1953 Elaina Gardens	Pittsburgh	PA	15237	8859709185	nick.lind@example.com	t
36	Linda	Swaniawski	3040 Addison Ways	Penn Hills	PA	15235	7953579648	linda.swaniawski@example.com	t
37	Angel	Stiedemann	8775 Morgan Station	Penn Hills	PA	15235	9039975488	angel.stiedemann@example.com	t
38	Sunny	Mante	792 Wilkinson Village	Pittsburgh	PA	15237	7200003287	sunny.mante@example.com	t
39	Brenden	Funk	33449 Jordane Walk	McCandless	PA	15090	2483435319	brenden.funk@example.com	t
40	Nicolas	Beahan	59235 Joany Route	Shaler	PA	15209	6788605191	nicolas.beahan@example.com	t
41	Selina	Turcotte	68167 Labadie Prairie	Shaler	PA	15209	5631032286	selina.turcotte@example.com	t
42	Oliver	Towne	9508 Beer Mall	Penn Hills	PA	15235	5142402390	oliver.towne@example.com	t
43	Lilliana	Smitham	8180 Bosco Inlet	Shaler	PA	15209	4397551438	lilliana.smitham@example.com	t
44	Nikita	Quigley	7120 Jasmin Extensions	Penn Hills	PA	15235	8648042774	nikita.quigley@example.com	t
45	Marco	Hauck	334 Reinhold Streets	Pittsburgh	PA	15212	5736733523	marco.hauck@example.com	t
46	Esperanza	Fisher	57297 Humberto Knolls	McCandless	PA	15090	0877625095	esperanza.fisher@example.com	t
47	Delbert	Bosco	180 Amos Green	Pittsburgh	PA	15213	2058801635	delbert.bosco@example.com	t
48	Heaven	Bogisich	3376 Windler Route	McCandless	PA	15090	4832208591	heaven.bogisich@example.com	t
49	Barton	Dooley	390 Leuschke Green	Penn Hills	PA	15235	3733220334	barton.dooley@example.com	t
50	Sarah	Borer	73067 Ted Heights	Pittsburgh	PA	15212	4422683338	sarah.borer@example.com	t
51	Johnpaul	Rohan	240 Pacocha Dale	Pittsburgh	PA	15237	6707345242	johnpaul.rohan@example.com	t
52	Bonnie	Turner	64738 Hilda Turnpike	Pittsburgh	PA	15212	2884829083	bonnie.turner@example.com	t
53	Hollis	Grant	9623 Duane Ranch	Pittsburgh	PA	15237	4472390241	hollis.grant@example.com	t
54	Edgar	Wolff	4948 Glover Curve	Pittsburgh	PA	15237	5511544064	edgar.wolff@example.com	t
55	Leo	Block	469 Trevor Ports	Pittsburgh	PA	15212	9789448128	leo.block@example.com	t
56	Marta	Nitzsche	7002 Hal Crossing	Pittsburgh	PA	15212	0242465722	marta.nitzsche@example.com	t
57	Amelia	Harber	37052 Kevon Underpass	Penn Hills	PA	15235	7467301419	amelia.harber@example.com	t
58	Michael	Doyle	1077 Laury Crossroad	Penn Hills	PA	15235	4168306779	michael.doyle@example.com	t
59	Sincere	Kemmer	496 Oberbrunner Highway	McCandless	PA	15090	1708057016	sincere.kemmer@example.com	t
60	Athena	White	18402 Golden Freeway	Penn Hills	PA	15235	5754706856	athena.white@example.com	t
61	Christ	Erdman	841 Gorczany Brook	Pittsburgh	PA	15213	1855464360	christ.erdman@example.com	t
62	Eunice	Stokes	54868 Crist Well	Pittsburgh	PA	15212	5778586808	eunice.stokes@example.com	t
63	Dulce	Gleason	700 Adalberto Plain	McCandless	PA	15090	4285882782	dulce.gleason@example.com	t
64	Domenica	Kautzer	95874 Hunter Turnpike	Penn Hills	PA	15235	3918926473	domenica.kautzer@example.com	t
65	Gerda	Olson	1822 Joy Underpass	Penn Hills	PA	15235	7456611082	gerda.olson@example.com	t
66	Elsa	Mertz	200 Sigrid Flats	Pittsburgh	PA	15237	5292439450	elsa.mertz@example.com	t
67	Alexander	Pfeffer	880 Albina Summit	McCandless	PA	15090	2765394509	alexander.pfeffer@example.com	t
68	Terry	Rosenbaum	54758 Candida Mountain	Pittsburgh	PA	15237	9058222197	terry.rosenbaum@example.com	t
69	Yazmin	Homenick	4456 Lazaro Stravenue	Penn Hills	PA	15235	4875950428	yazmin.homenick@example.com	t
70	Liam	White	9350 Rowe Club	Pittsburgh	PA	15213	0053306505	liam.white@example.com	t
71	Santa	O'Keefe	676 Cydney Pine	Pittsburgh	PA	15212	2973902180	santa.o'keefe@example.com	t
72	Dino	Dach	1982 Brielle Parks	Pittsburgh	PA	15237	8937094877	dino.dach@example.com	t
73	Rory	Parker	327 Hettinger Divide	Pittsburgh	PA	15212	0824064111	rory.parker@example.com	t
74	Adrain	Green	54340 Wuckert Ports	Pittsburgh	PA	15213	2865402122	adrain.green@example.com	t
75	Vernice	Labadie	9165 Fern Parkways	Shaler	PA	15209	3234304430	vernice.labadie@example.com	t
76	Stefanie	Mann	349 Rutherford Drive	Pittsburgh	PA	15237	3168230980	stefanie.mann@example.com	t
77	Christy	Streich	34015 Hilpert Villages	Shaler	PA	15209	2756264611	christy.streich@example.com	t
78	Adele	Bins	678 Beier Vista	McCandless	PA	15090	1676291144	adele.bins@example.com	t
79	Andres	Anderson	2735 Mafalda Mill	Shaler	PA	15209	5567223927	andres.anderson@example.com	t
80	Sherwood	Klein	3565 Lura Course	Pittsburgh	PA	15212	1815756623	sherwood.klein@example.com	t
81	Salvador	Kilback	847 Mary Lake	Pittsburgh	PA	15237	7930625384	salvador.kilback@example.com	t
82	Georgette	Bahringer	83567 Belle Throughway	Pittsburgh	PA	15212	1965820375	georgette.bahringer@example.com	t
83	Kaylin	Douglas	3520 Kellie Gateway	Pittsburgh	PA	15212	8974020211	kaylin.douglas@example.com	t
84	Melyssa	Ferry	156 Marks Creek	Shaler	PA	15209	6874156313	melyssa.ferry@example.com	t
85	Alvera	Goldner	583 Howell Flats	McCandless	PA	15090	4333413882	alvera.goldner@example.com	t
86	Jaylon	Hahn	50180 Zboncak Manor	Pittsburgh	PA	15213	0997146122	jaylon.hahn@example.com	t
87	Petra	Effertz	53278 Beahan Squares	Shaler	PA	15209	0476006607	petra.effertz@example.com	t
88	Horacio	Mayert	7822 Ethelyn Port	McCandless	PA	15090	4726449492	horacio.mayert@example.com	t
89	Delphia	Hahn	1249 Runolfsson Terrace	Pittsburgh	PA	15237	5260615877	delphia.hahn@example.com	t
90	Yasmin	Wuckert	6340 Kris Rapid	Pittsburgh	PA	15237	8092309947	yasmin.wuckert@example.com	t
91	Richard	Mante	874 Kshlerin Crossroad	Penn Hills	PA	15235	3791427125	richard.mante@example.com	t
92	Scarlett	Dooley	7699 Doyle Garden	Pittsburgh	PA	15237	1453976452	scarlett.dooley@example.com	t
93	Emmie	MacGyver	9384 Ricky View	McCandless	PA	15090	3160971908	emmie.macgyver@example.com	t
94	Edwardo	Mills	51073 Heidenreich Common	Penn Hills	PA	15235	5452643285	edwardo.mills@example.com	t
95	Scot	Tromp	8223 Pacocha Roads	Pittsburgh	PA	15237	1618292030	scot.tromp@example.com	t
96	Nikko	King	94012 Schimmel Ports	Pittsburgh	PA	15237	6486843376	nikko.king@example.com	t
97	Penelope	Bartoletti	898 Carrie Shores	Pittsburgh	PA	15213	3173363499	penelope.bartoletti@example.com	t
98	Lon	Jewess	11830 Ernser Plaza	Pittsburgh	PA	15213	9220214577	lon.jewess@example.com	t
99	Wilson	Zulauf	760 Sylvester Passage	Penn Hills	PA	15235	7815094980	wilson.zulauf@example.com	t
100	Santino	Rempel	733 Hyatt Flats	Pittsburgh	PA	15213	0545788967	santino.rempel@example.com	t
101	Unique	Beier	3719 Ramona Trace	Shaler	PA	15209	8608081287	unique.beier@example.com	t
102	Madisen	Schumm	20582 Rollin Cliffs	Shaler	PA	15209	0387638319	madisen.schumm@example.com	t
103	Monica	Roberts	70190 Bartoletti Estate	Pittsburgh	PA	15237	9167087637	monica.roberts@example.com	t
104	Issac	Daniel	76421 Garret Court	Penn Hills	PA	15235	8065608530	issac.daniel@example.com	t
105	Breanna	Hagenes	97196 Altenwerth Summit	Shaler	PA	15209	9982647177	breanna.hagenes@example.com	t
106	Torrey	Bruen	20824 McClure Stravenue	McCandless	PA	15090	6100767186	torrey.bruen@example.com	t
107	Andre	Quigley	6772 Ana Ports	McCandless	PA	15090	1619350641	andre.quigley@example.com	t
108	Elmo	Cummerata	8812 Erika Mill	Pittsburgh	PA	15213	9705623953	elmo.cummerata@example.com	t
109	Karina	Mitchell	792 Hamill Crest	Pittsburgh	PA	15212	9618725991	karina.mitchell@example.com	t
110	Leora	Reichert	509 Merle Spur	McCandless	PA	15090	1842861099	leora.reichert@example.com	t
111	Coty	Jacobson	26822 Monahan Wall	Shaler	PA	15209	6433800106	coty.jacobson@example.com	t
112	Alvena	Cormier	706 Conroy Locks	Pittsburgh	PA	15213	9301531762	alvena.cormier@example.com	t
113	Haley	Funk	4585 Howell Keys	Shaler	PA	15209	0170834340	haley.funk@example.com	t
114	Libbie	Bogisich	66126 Bernhard Pines	Penn Hills	PA	15235	5721180997	libbie.bogisich@example.com	t
115	Antone	Oberbrunner	60188 Timmothy Street	McCandless	PA	15090	6635673146	antone.oberbrunner@example.com	t
116	Isabel	Hoppe	5749 Isaias Fall	Pittsburgh	PA	15237	5510131125	isabel.hoppe@example.com	t
117	Christiana	Schmidt	400 Smith Orchard	Penn Hills	PA	15235	2770645568	christiana.schmidt@example.com	t
118	Otilia	Quigley	84483 Osinski Glen	Shaler	PA	15209	7161235269	otilia.quigley@example.com	t
119	Schuyler	Doyle	9989 Loy Shoals	Penn Hills	PA	15235	2594186667	schuyler.doyle@example.com	t
120	Ila	Hahn	97776 Jacinto Ridge	Pittsburgh	PA	15213	2797470552	ila.hahn@example.com	t
\.


--
-- Name: owners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('owners_id_seq', 120, true);


--
-- Data for Name: pets; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY pets (id, name, animal_id, owner_id, female, date_of_birth, active) FROM stdin;
1	Caspian	4	1	f	2009-12-30	t
2	Bojangles	3	1	t	2005-09-03	t
3	Copper	3	2	f	2005-08-01	t
4	Bongo	5	3	t	2003-06-18	t
5	Yeller	2	4	f	2006-08-13	t
6	Dusty	2	5	f	2003-03-19	t
7	Groucho	2	6	f	2007-02-14	t
8	Weeble	2	7	t	2003-06-01	t
9	Weeble	4	7	t	2007-11-04	t
10	Mambo	3	7	t	2003-10-27	t
11	Sparky	4	8	t	2008-03-04	t
12	Meatball	4	8	f	2011-09-27	t
13	Montana	5	8	t	2007-01-12	t
14	Bojangles	4	9	t	2003-05-11	t
15	Weeble	3	9	f	2006-07-01	t
16	Yeller	1	10	t	2005-12-10	t
17	Bama	5	10	t	2009-09-24	t
18	Snuggles	5	10	f	2007-07-05	t
19	Bama	3	11	f	2010-04-24	t
20	Spot	3	11	f	2004-05-21	t
21	Mai Tai	1	11	f	2006-09-30	t
22	Fang	3	12	f	2006-04-03	t
23	Cali	2	12	t	2003-03-05	t
24	Bama	5	12	f	2011-05-15	t
25	Bongo	5	13	f	2011-12-18	t
26	Sparky	3	14	f	2006-11-23	t
27	Cali	1	15	f	2010-02-02	t
28	Lucky	4	15	t	2004-01-24	t
29	Snuggles	5	15	f	2011-04-04	t
30	BJ	5	16	t	2006-04-01	t
31	Bongo	4	17	f	2010-10-20	t
32	Fang	2	17	t	2008-12-06	t
33	Caspian	3	17	f	2009-05-06	t
34	Mambo	4	18	t	2004-11-08	t
35	Meatball	2	18	t	2009-03-12	t
36	Spot	1	19	f	2009-04-14	t
37	Lucky	4	19	t	2010-01-08	t
38	Dusty	5	20	t	2003-11-02	t
39	Zaphod	1	20	t	2006-12-19	t
40	Zaphod	4	20	t	2008-02-09	t
41	Lucky	4	21	f	2003-10-16	t
42	Fozzie	5	21	t	2003-12-13	t
43	Montana	3	21	t	2004-08-23	t
44	Cali	1	22	t	2004-07-02	t
45	Dakota	2	22	t	2005-09-28	t
46	Snuggles	5	22	t	2004-06-15	t
47	CJ	1	23	f	2007-11-10	t
48	Dakota	4	23	t	2008-12-29	t
49	TJ	5	23	t	2009-04-07	t
50	Fang	4	24	f	2009-06-04	t
51	Montana	1	24	t	2002-12-23	t
52	Fang	4	25	f	2011-03-25	t
53	Mai Tai	5	25	f	2010-01-15	t
54	Pickles	4	25	t	2006-05-20	t
55	Pork Chop	4	26	f	2012-03-01	t
56	CJ	2	26	f	2009-06-24	t
57	Montana	4	26	f	2009-05-12	t
58	Bongo	3	27	f	2004-12-16	t
59	Zaphod	5	27	f	2010-12-16	t
60	Tango	1	27	t	2005-11-17	t
61	Yeller	4	28	t	2007-07-14	t
62	CJ	5	28	t	2007-03-04	t
63	Buddy	3	29	f	2011-11-06	t
64	Meatball	3	29	f	2005-10-10	t
65	Zaphod	1	30	t	2010-11-27	t
66	Weeble	5	30	t	2004-12-05	t
67	Lucky	2	31	t	2003-07-23	t
68	Fluffy	3	31	t	2011-12-11	t
69	Pickles	3	31	f	2004-05-14	t
70	BJ	5	32	t	2006-10-05	t
71	Bojangles	5	32	t	2008-07-19	t
72	Zaphod	2	33	f	2005-06-08	t
73	Fluffy	2	34	f	2011-04-25	t
74	Snuffles	1	35	t	2004-01-10	t
75	Pickles	3	36	f	2005-07-17	t
76	Mambo	5	37	f	2008-08-26	t
77	Yeller	3	37	t	2006-02-26	t
78	Fluffy	4	38	f	2011-06-07	t
79	Dusty	4	38	t	2011-10-20	t
80	Bojangles	4	39	f	2002-11-26	t
81	Dusty	4	39	t	2011-03-24	t
82	Weeble	3	39	t	2009-11-01	t
83	Nipper	4	40	t	2004-06-15	t
84	Nipper	3	41	t	2008-01-18	t
85	Snuffles	5	42	f	2009-04-17	t
86	Tongo	5	43	f	2005-10-15	t
87	Fozzie	2	44	f	2011-01-14	t
88	Montana	4	44	t	2012-05-02	t
89	Groucho	1	44	t	2003-04-29	t
90	Meatball	4	45	t	2011-04-24	t
91	Bojangles	4	45	f	2005-10-25	t
92	Tongo	2	46	f	2005-11-30	t
93	Mai Tai	5	47	t	2005-02-09	t
94	Mambo	4	47	f	2010-11-06	t
95	Nipper	2	48	f	2005-09-22	t
96	Tango	1	48	t	2011-12-06	t
97	Sparky	5	48	f	2010-04-15	t
98	Bongo	1	49	f	2004-07-04	t
99	Dusty	4	49	f	2003-03-15	t
100	Bull	2	50	f	2004-02-11	t
101	Spot	5	51	f	2010-02-25	t
102	TJ	1	52	f	2003-08-31	t
103	Mambo	1	53	f	2011-06-16	t
104	BJ	5	53	f	2010-09-18	t
105	Spot	4	53	f	2005-06-02	t
106	Bongo	2	54	t	2007-07-01	t
107	Yeller	4	55	f	2006-08-04	t
108	Buddy	4	55	f	2006-08-25	t
109	Buddy	2	55	f	2011-03-01	t
110	Buttercup	1	56	f	2006-03-24	t
111	Weeble	5	57	f	2005-12-15	t
112	Cali	4	58	f	2003-11-24	t
113	Lucky	2	58	t	2002-12-06	t
114	BJ	5	58	t	2011-02-15	t
115	CJ	2	59	f	2010-07-21	t
116	Fozzie	5	59	f	2007-09-04	t
117	Pickles	2	60	t	2009-03-20	t
118	Pork Chop	5	61	f	2003-05-05	t
119	Dusty	5	61	f	2006-06-29	t
120	Pork Chop	5	62	t	2010-03-12	t
121	Sparky	4	63	t	2005-12-29	t
122	Dakota	3	63	t	2011-04-07	t
123	Zaphod	2	64	f	2005-08-28	t
124	Zaphod	3	64	t	2009-02-15	t
125	Fluffy	1	64	f	2011-12-28	t
126	Sparky	5	65	f	2011-02-12	t
127	Snuggles	4	65	t	2003-01-11	t
128	Snuggles	1	65	t	2003-03-29	t
129	Spot	1	66	f	2009-04-17	t
130	Tango	4	66	t	2003-01-09	t
131	Bull	3	67	t	2012-04-11	t
132	CJ	4	68	f	2003-12-10	t
133	Zaphod	4	68	t	2007-10-11	t
134	Spot	5	69	f	2008-11-29	t
135	CJ	1	69	f	2005-10-11	t
136	Tongo	1	70	t	2002-12-27	t
137	Snuggles	4	70	f	2003-03-16	t
138	Yeller	1	70	t	2012-01-20	t
139	Snuggles	1	71	f	2005-06-23	t
140	Spot	3	71	t	2008-09-30	t
141	Fang	4	72	f	2004-03-26	t
142	Fozzie	2	73	f	2010-02-13	t
143	Copper	4	73	t	2011-06-18	t
144	Dakota	1	74	f	2011-02-18	t
145	Spot	2	74	f	2012-02-04	t
146	Nipper	1	75	f	2010-01-02	t
147	Pork Chop	5	75	t	2010-09-24	t
148	BJ	3	76	t	2006-11-02	t
149	Tongo	1	76	f	2003-03-03	t
150	Pork Chop	4	77	f	2012-03-09	t
151	Bull	1	77	t	2011-07-24	t
152	Buttercup	1	77	t	2007-09-26	t
153	Zaphod	5	78	f	2011-07-09	t
154	Bama	2	78	f	2011-11-11	t
155	Fozzie	2	79	f	2006-12-07	t
156	Tango	5	79	t	2007-07-03	t
157	Pickles	1	79	t	2005-05-30	t
158	Tongo	5	80	t	2008-10-14	t
159	Buttercup	1	80	t	2008-03-07	t
160	TJ	5	81	f	2008-05-30	t
161	Fluffy	3	82	t	2011-08-30	t
162	Fang	3	82	f	2008-04-22	t
163	Yeller	2	82	t	2011-04-10	t
164	Montana	5	83	t	2007-04-23	t
165	Polo	3	84	f	2008-02-16	t
166	Meatball	5	85	f	2012-03-22	t
167	Pickles	3	85	f	2006-11-23	t
168	Fang	3	86	t	2010-01-10	t
169	CJ	4	86	t	2005-05-06	t
170	Bongo	1	86	f	2008-03-22	t
171	Pickles	3	87	f	2010-06-18	t
172	Bongo	3	87	f	2004-09-27	t
173	Zaphod	3	88	f	2011-09-22	t
174	Buddy	5	88	t	2009-05-01	t
175	Nipper	4	88	f	2009-06-25	t
176	Pickles	2	89	f	2005-12-28	t
177	CJ	4	90	f	2008-10-14	t
178	TJ	5	91	f	2006-08-23	t
179	Tango	5	91	t	2006-09-27	t
180	Polo	3	92	f	2005-04-19	t
181	Copper	2	92	t	2004-08-17	t
182	TJ	1	93	f	2004-07-22	t
183	Meatball	3	93	f	2008-10-19	t
184	Fluffy	3	94	t	2003-03-09	t
185	CJ	3	94	f	2003-04-18	t
186	Spot	2	95	f	2010-12-31	t
187	Buddy	3	95	t	2003-03-13	t
188	Polo	1	95	f	2011-01-29	t
189	Nipper	3	96	f	2011-03-16	t
190	Cali	3	97	t	2009-08-24	t
191	Buddy	1	97	f	2002-11-28	t
192	Zaphod	1	98	f	2007-04-23	t
193	Bama	2	99	f	2003-08-23	t
194	Bama	3	100	t	2007-09-22	t
195	Zaphod	3	100	f	2010-09-06	t
196	Snuffles	4	101	t	2010-09-24	t
197	Weeble	5	101	t	2008-05-18	t
198	Dusty	3	102	t	2006-11-02	t
199	Bojangles	3	102	f	2003-05-18	t
200	Zaphod	2	103	f	2011-04-02	t
201	Snuffles	3	103	t	2011-03-17	t
202	Buddy	1	104	f	2002-12-26	t
203	Montana	5	104	t	2002-11-17	t
204	TJ	2	104	f	2010-02-15	t
205	Tongo	5	105	t	2005-12-14	t
206	Buttercup	3	105	t	2010-08-25	t
207	Nipper	3	106	f	2010-09-20	t
208	Zaphod	3	106	t	2008-12-22	t
209	Pickles	2	107	t	2011-09-22	t
210	Buddy	2	107	t	2004-12-18	t
211	Fang	2	107	f	2009-05-30	t
212	Snuffles	4	108	t	2010-02-16	t
213	Nipper	2	108	t	2003-07-16	t
214	Pork Chop	2	109	t	2007-07-05	t
215	Bama	5	110	f	2005-01-16	t
216	Caspian	5	110	t	2006-08-05	t
217	Snuffles	3	111	t	2009-08-14	t
218	Buddy	2	111	f	2004-02-16	t
219	Bongo	3	111	t	2010-07-09	t
220	Tango	3	112	t	2008-02-20	t
221	Yeller	1	113	t	2006-10-13	t
222	BJ	3	114	t	2009-09-20	t
223	Spot	4	114	t	2009-09-14	t
224	Bull	5	114	f	2010-10-09	t
225	Yeller	4	115	f	2009-01-17	t
226	Fozzie	2	115	t	2010-12-22	t
227	Snuffles	4	115	t	2010-07-20	t
228	Tango	4	116	f	2012-03-01	t
229	Pickles	5	117	f	2011-04-02	t
230	BJ	5	117	t	2008-08-30	t
231	Tango	3	118	t	2006-05-22	t
232	TJ	2	119	t	2007-05-28	t
233	Bojangles	4	119	t	2003-10-23	t
234	Bojangles	1	119	f	2008-09-29	t
235	TJ	1	120	f	2010-03-28	t
236	Dakota	2	120	t	2008-10-01	t
237	Nipper	4	120	t	2007-09-04	t
\.


--
-- Name: pets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('pets_id_seq', 237, true);


--
-- Data for Name: procedure_costs; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY procedure_costs (id, procedure_id, cost, start_date, end_date) FROM stdin;
1	1	12500	2012-08-09	\N
2	1	11250	2012-04-09	2012-08-09
3	2	15000	2012-07-09	\N
4	2	13500	2012-03-09	2012-07-09
5	3	4000	2012-06-09	\N
6	3	3600	2012-03-09	2012-06-09
7	4	120000	2012-07-09	\N
8	4	108000	2012-04-09	2012-07-09
9	5	40000	2012-08-09	\N
10	5	36000	2012-04-09	2012-08-09
11	6	7500	2012-07-09	\N
12	6	6750	2012-04-09	2012-07-09
13	7	15000	2012-08-09	\N
14	7	13500	2012-02-09	2012-08-09
15	8	15000	2012-07-09	\N
16	8	13500	2012-03-09	2012-07-09
17	9	5000	2012-07-09	\N
18	9	4500	2012-04-09	2012-07-09
\.


--
-- Name: procedure_costs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('procedure_costs_id_seq', 18, true);


--
-- Data for Name: procedures; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY procedures (id, name, description, length_of_time, active) FROM stdin;
1	Check-up	An amazing procedure	30	t
2	Examination	An amazing procedure	30	t
3	Grooming	An amazing procedure	15	t
4	Major Surgery	An amazing procedure	180	t
5	Minor Surgery	An amazing procedure	75	t
6	Observation	An amazing procedure	180	t
7	Observation, Extended	An amazing procedure	540	t
8	Testing	An amazing procedure	10	t
9	X-ray	An amazing procedure	10	t
\.


--
-- Name: procedures_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('procedures_id_seq', 9, true);


--
-- Data for Name: treatments; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY treatments (id, visit_id, procedure_id, successful, discount) FROM stdin;
1	1	9	t	0
2	1	1	t	0
3	2	6	t	0
4	2	4	t	0
5	3	8	t	0
6	3	3	t	0
7	4	4	t	0
8	4	1	t	0
9	5	2	t	0
10	5	8	t	0
11	6	6	t	0
12	6	7	t	0
13	7	6	t	0
14	7	7	t	0
15	7	4	t	0.299999999999999989
16	8	4	t	0
17	8	2	t	0
18	9	5	t	0
19	9	2	t	0
20	10	7	t	0
21	10	4	t	0
22	11	4	t	0
23	11	8	t	0
24	11	9	t	0.299999999999999989
25	12	8	t	0
26	12	5	t	0
27	13	3	t	0
28	13	5	t	0
29	14	6	t	0
30	14	1	t	0
31	15	8	t	0
32	15	6	t	0
33	16	7	t	0
34	16	6	t	0
35	17	2	t	0
36	17	1	t	0
37	17	8	t	0.299999999999999989
38	18	7	t	0
39	18	8	t	0.25
40	18	1	t	0.299999999999999989
41	19	4	t	0
42	19	9	t	0
43	20	6	t	0
44	20	8	t	0.25
45	21	5	t	0
46	21	3	t	0
47	22	8	t	0
48	22	6	t	0
49	23	9	t	0
50	23	2	t	0
51	24	8	t	0
52	24	2	t	0
53	24	4	t	0.299999999999999989
54	25	1	t	0
55	25	9	t	0
56	25	4	t	0.299999999999999989
57	26	3	t	0
58	26	9	t	0
59	27	5	t	0
60	27	3	t	0
61	28	1	t	0
62	28	2	t	0
63	29	4	t	0
64	29	9	t	0
65	30	1	t	0
66	30	5	t	0
67	30	4	t	0.299999999999999989
68	31	6	t	0
69	31	9	t	0.25
70	31	2	t	0.299999999999999989
71	32	6	t	0
72	32	3	t	0
73	33	1	t	0
74	33	5	t	0
75	33	7	t	0.299999999999999989
76	34	8	t	0
77	34	4	t	0
78	35	7	t	0
79	35	6	t	0
80	36	9	t	0
81	36	5	t	0
82	36	1	t	0.299999999999999989
83	37	5	t	0
84	37	8	t	0
85	37	6	t	0.299999999999999989
86	38	3	t	0
87	38	9	t	0
88	38	1	t	0.299999999999999989
89	39	3	t	0
90	39	1	t	0
91	39	4	t	0.299999999999999989
92	40	8	t	0
93	40	5	t	0
94	41	5	t	0
95	41	1	t	0
96	42	1	t	0
97	42	7	t	0
98	42	2	t	0.299999999999999989
99	43	8	t	0
100	43	2	t	0
101	43	7	t	0.299999999999999989
102	44	4	t	0
103	44	8	t	0
104	45	6	t	0
105	45	9	t	0
106	46	7	t	0
107	46	1	t	0
108	47	9	t	0
109	47	1	t	0
110	47	2	t	0.299999999999999989
111	48	1	t	0
112	48	5	t	0
113	49	8	t	0
114	49	2	t	0
115	49	7	t	0.299999999999999989
116	50	5	t	0
117	50	9	t	0
118	50	2	t	0.299999999999999989
119	51	6	t	0
120	51	2	t	0
121	52	1	t	0
122	52	8	t	0
123	53	1	t	0
124	53	5	t	0
125	53	8	t	0.299999999999999989
126	54	7	t	0
127	54	8	t	0
128	55	9	t	0
129	55	2	t	0
130	56	9	t	0
131	56	3	t	0
132	57	2	t	0
133	57	9	t	0
134	58	7	t	0
135	58	4	t	0
136	59	3	t	0
137	59	5	t	0
138	60	8	t	0
139	60	1	t	0
140	60	2	t	0.299999999999999989
141	61	6	t	0
142	61	9	t	0
143	62	5	t	0
144	62	1	t	0.25
145	62	3	t	0.299999999999999989
146	63	4	t	0
147	63	1	t	0.25
148	64	3	t	0
149	64	4	t	0
150	65	3	t	0
151	65	9	t	0
152	66	7	t	0
153	66	9	t	0
154	67	1	t	0
155	67	5	t	0
156	68	7	t	0
157	68	3	t	0
158	69	4	t	0
159	69	2	t	0
160	69	5	t	0.299999999999999989
161	70	6	t	0
162	70	7	t	0.25
163	71	5	t	0
164	71	8	t	0
165	71	6	t	0.299999999999999989
166	72	1	t	0
167	72	3	t	0
168	72	6	t	0.299999999999999989
169	73	4	t	0
170	73	1	t	0
171	74	8	t	0
172	74	2	t	0
173	75	6	t	0
174	75	5	t	0
175	75	4	t	0.299999999999999989
176	76	7	t	0
177	76	4	t	0
178	77	2	t	0
179	77	4	t	0
180	77	1	t	0.299999999999999989
181	78	9	t	0
182	78	2	t	0
183	79	6	t	0
184	79	2	t	0
185	79	3	t	0.299999999999999989
186	80	6	t	0
187	80	5	t	0
188	81	1	t	0
189	81	7	t	0.25
190	82	6	t	0
191	82	9	t	0
192	83	7	t	0
193	83	4	t	0
194	84	9	t	0
195	84	5	t	0
196	85	2	t	0
197	85	9	t	0
198	85	5	t	0.299999999999999989
199	86	2	t	0
200	86	3	t	0
201	86	4	t	0.299999999999999989
202	87	8	t	0
203	87	4	t	0
204	88	5	t	0
205	88	4	t	0
206	89	6	t	0
207	89	9	t	0
208	90	9	t	0
209	90	1	t	0
210	90	6	t	0.299999999999999989
211	91	1	t	0
212	91	9	t	0
213	92	4	t	0
214	92	7	t	0.25
215	93	9	t	0
216	93	2	t	0
217	93	5	t	0.299999999999999989
218	94	8	t	0
219	94	1	t	0
220	95	2	t	0
221	95	6	t	0
222	96	3	t	0
223	96	1	t	0
224	97	7	t	0
225	97	3	t	0
226	97	9	t	0.299999999999999989
227	98	9	t	0
228	98	3	t	0
229	99	6	t	0
230	99	1	t	0
231	100	2	t	0
232	100	7	t	0.25
233	101	6	t	0
234	101	7	t	0
235	101	4	t	0.299999999999999989
236	102	6	t	0
237	102	8	t	0
238	103	4	t	0
239	103	9	t	0
240	104	5	t	0
241	104	2	t	0
242	105	4	t	0
243	105	6	t	0
244	106	5	t	0
245	106	8	t	0.25
246	106	1	t	0.299999999999999989
247	107	4	t	0
248	107	7	t	0
249	108	5	t	0
250	108	3	t	0
251	109	8	t	0
252	109	4	t	0
253	110	6	t	0
254	110	9	t	0
255	111	4	t	0
256	111	8	t	0
257	111	5	t	0.299999999999999989
258	112	9	t	0
259	112	4	t	0
260	112	3	t	0.5
261	113	3	t	0
262	113	2	t	0
263	114	4	t	0
264	114	5	t	0
265	115	9	t	0
266	115	2	t	0
267	115	4	t	0.299999999999999989
268	116	8	t	0
269	116	5	t	0
270	117	8	t	0
271	117	7	t	0
272	118	5	t	0
273	118	1	t	0
274	118	4	t	0.299999999999999989
275	119	3	t	0
276	119	9	t	0
277	120	7	t	0
278	120	5	t	0
279	121	5	t	0
280	121	6	t	0
281	122	1	t	0
282	122	4	t	0
283	123	5	t	0
284	123	8	t	0
285	124	1	t	0
286	124	7	t	0
287	124	4	t	0.299999999999999989
288	125	4	t	0
289	125	1	t	0
290	125	8	t	0.299999999999999989
291	126	8	t	0
292	126	7	t	0
293	127	8	t	0
294	127	2	t	0.25
295	128	3	t	0
296	128	4	t	0.25
297	129	9	t	0
298	129	4	t	0
299	129	3	t	0.299999999999999989
300	130	4	t	0
301	130	6	t	0
302	131	1	t	0
303	131	9	t	0
304	131	3	t	0.299999999999999989
305	132	4	t	0
306	132	9	t	0
307	133	9	t	0
308	133	8	t	0
309	133	7	t	0.299999999999999989
310	134	2	t	0
311	134	8	t	0.25
312	134	3	t	0.299999999999999989
313	135	6	t	0
314	135	2	t	0
315	136	4	t	0
316	136	7	t	0
317	137	4	t	0
318	137	7	t	0
319	138	7	t	0
320	138	2	t	0
321	139	4	t	0
322	139	5	t	0
323	140	4	t	0
324	140	3	t	0
325	140	9	t	0.299999999999999989
326	141	7	t	0
327	141	5	t	0
328	142	7	t	0
329	142	2	t	0
330	143	2	t	0
331	143	5	t	0
332	144	6	t	0
333	144	7	t	0.25
334	145	3	t	0
335	145	7	t	0
336	146	2	t	0
337	146	3	t	0
338	146	7	t	0.299999999999999989
339	147	6	t	0
340	147	5	t	0
341	147	7	t	0.299999999999999989
342	148	5	t	0
343	148	1	t	0.25
344	149	4	t	0
345	149	6	t	0
346	149	7	t	0.299999999999999989
347	150	3	t	0
348	150	5	t	0
349	150	6	t	0.299999999999999989
350	151	5	t	0
351	151	1	t	0
352	152	3	t	0
353	152	4	t	0
354	152	2	t	0.299999999999999989
355	153	3	t	0
356	153	5	t	0
357	153	2	t	0.299999999999999989
358	154	4	t	0
359	154	8	t	0
360	155	1	t	0
361	155	7	t	0
362	156	4	t	0
363	156	6	t	0
364	157	4	t	0
365	157	1	t	0
366	158	7	t	0
367	158	8	t	0.25
368	159	2	t	0
369	159	8	t	0
370	160	7	t	0
371	160	2	t	0
372	161	8	t	0
373	161	7	t	0
374	162	4	t	0
375	162	6	t	0
376	163	8	t	0
377	163	4	t	0
378	164	4	t	0
379	164	2	t	0
380	165	5	t	0
381	165	8	t	0
382	166	4	t	0
383	166	9	t	0
384	166	5	t	0.299999999999999989
385	167	3	t	0
386	167	7	t	0
387	168	2	t	0
388	168	4	t	0
389	169	7	t	0
390	169	2	t	0
391	169	5	t	0.299999999999999989
392	170	7	t	0
393	170	3	t	0.25
394	170	6	t	0.299999999999999989
395	171	8	t	0
396	171	9	t	0
397	172	6	t	0
398	172	8	t	0
399	172	3	t	0.5
400	173	5	t	0
401	173	4	t	0
402	174	9	t	0
403	174	3	t	0
404	175	6	t	0
405	175	2	t	0
406	175	9	t	0.299999999999999989
407	176	5	t	0
408	176	6	t	0.25
409	177	7	t	0
410	177	9	t	0
411	178	4	t	0
412	178	9	t	0
413	178	3	t	0.299999999999999989
414	179	3	t	0
415	179	7	t	0
416	180	1	t	0
417	180	3	t	0
418	181	2	t	0
419	181	4	t	0
420	182	8	t	0
421	182	1	t	0
422	183	6	t	0
423	183	8	t	0
424	183	5	t	0.299999999999999989
425	184	5	t	0
426	184	6	t	0
427	185	8	t	0
428	185	1	t	0
429	186	9	t	0
430	186	8	t	0
431	187	1	t	0
432	187	2	t	0
433	187	8	t	0.299999999999999989
434	188	1	t	0
435	188	3	t	0.25
436	188	4	t	0.299999999999999989
437	189	1	t	0
438	189	9	t	0
439	190	5	t	0
440	190	2	t	0
441	190	3	t	0.299999999999999989
442	191	1	t	0
443	191	4	t	0
444	191	5	t	0.299999999999999989
445	192	1	t	0
446	192	5	t	0
447	193	4	t	0
448	193	8	t	0
449	193	7	t	0.299999999999999989
450	194	3	t	0
451	194	7	t	0
452	195	7	t	0
453	195	4	t	0
454	196	3	t	0
455	196	6	t	0
456	197	7	t	0
457	197	9	t	0
458	198	2	t	0
459	198	1	t	0.25
460	198	9	t	0.299999999999999989
461	199	8	t	0
462	199	7	t	0
463	200	7	t	0
464	200	6	t	0
465	201	9	t	0
466	201	3	t	0
467	202	7	t	0
468	202	1	t	0
469	203	3	t	0
470	203	7	t	0
471	203	8	t	0.299999999999999989
472	204	9	t	0
473	204	8	t	0
474	204	5	t	0.5
475	205	4	t	0
476	205	9	t	0
477	205	6	t	0.299999999999999989
478	206	8	t	0
479	206	4	t	0
480	206	6	t	0.299999999999999989
481	207	1	t	0
482	207	5	t	0
483	207	8	t	0.299999999999999989
484	208	6	t	0
485	208	8	t	0
486	208	3	t	0.299999999999999989
487	209	8	t	0
488	209	9	t	0
489	210	6	t	0
490	210	8	t	0
491	211	6	t	0
492	211	5	t	0
493	211	4	t	0.5
494	212	5	t	0
495	212	6	t	0.25
496	213	5	t	0
497	213	2	t	0
498	213	3	t	0.299999999999999989
499	214	1	t	0
500	214	5	t	0
501	215	6	t	0
502	215	5	t	0
503	215	7	t	0.299999999999999989
504	216	2	t	0
505	216	1	t	0
506	217	7	t	0
507	217	9	t	0
508	218	8	t	0
509	218	7	t	0
510	218	3	t	0.299999999999999989
511	219	2	t	0
512	219	3	t	0
513	219	8	t	0.5
514	220	8	t	0
515	220	7	t	0
516	220	1	t	0.299999999999999989
517	221	1	t	0
518	221	5	t	0
519	221	3	t	0.299999999999999989
520	222	6	t	0
521	222	4	t	0
522	223	9	t	0
523	223	4	t	0
524	224	3	t	0
525	224	6	t	0
526	225	1	t	0
527	225	2	t	0
528	225	6	t	0.299999999999999989
529	226	2	t	0
530	226	5	t	0
531	227	9	t	0
532	227	7	t	0.25
533	228	9	t	0
534	228	2	t	0
535	229	6	t	0
536	229	8	t	0
537	229	3	t	0.299999999999999989
538	230	7	t	0
539	230	8	t	0
540	230	1	t	0.299999999999999989
541	231	3	t	0
542	231	2	t	0
543	231	7	t	0.299999999999999989
544	232	3	t	0
545	232	1	t	0
546	233	3	t	0
547	233	5	t	0
548	234	6	t	0
549	234	4	t	0
550	235	9	t	0
551	235	8	t	0
552	236	4	t	0
553	236	9	t	0
554	236	8	t	0.299999999999999989
555	237	1	t	0
556	237	6	t	0
557	238	1	t	0
558	238	8	t	0.25
559	239	6	t	0
560	239	4	t	0.25
561	239	2	t	0.299999999999999989
562	240	3	t	0
563	240	7	t	0
564	241	2	t	0
565	241	1	t	0.25
566	241	9	t	0.299999999999999989
567	242	3	t	0
568	242	2	t	0
569	243	8	t	0
570	243	6	t	0
571	243	3	t	0.299999999999999989
572	244	1	t	0
573	244	6	t	0
574	244	4	t	0.299999999999999989
575	245	8	t	0
576	245	4	t	0
577	245	9	t	0.299999999999999989
578	246	8	t	0
579	246	4	t	0
580	247	3	t	0
581	247	6	t	0
582	248	7	t	0
583	248	8	t	0
584	249	5	t	0
585	249	4	t	0
586	250	5	t	0
587	250	8	t	0
588	251	6	t	0
589	251	5	t	0
590	252	2	t	0
591	252	3	t	0
592	252	7	t	0.299999999999999989
593	253	8	t	0
594	253	2	t	0
595	254	5	t	0
596	254	1	t	0.25
597	255	2	t	0
598	255	9	t	0
599	256	7	t	0
600	256	3	t	0
601	257	5	t	0
602	257	9	t	0
603	258	6	t	0
604	258	8	t	0.25
605	259	6	t	0
606	259	3	t	0
607	260	2	t	0
608	260	9	t	0
609	261	1	t	0
610	261	4	t	0
611	261	8	t	0.299999999999999989
612	262	8	t	0
613	262	5	t	0
614	263	4	t	0
615	263	5	t	0
616	263	6	t	0.299999999999999989
617	264	3	t	0
618	264	1	t	0
619	265	3	t	0
620	265	8	t	0
621	265	6	t	0.299999999999999989
622	266	4	t	0
623	266	2	t	0
624	266	3	t	0.299999999999999989
625	267	3	t	0
626	267	2	t	0.25
627	267	7	t	0.299999999999999989
628	268	1	t	0
629	268	9	t	0
630	269	9	t	0
631	269	1	t	0
632	270	4	t	0
633	270	6	t	0
634	270	2	t	0.299999999999999989
635	271	2	t	0
636	271	1	t	0
637	271	8	t	0.299999999999999989
638	272	2	t	0
639	272	5	t	0
640	273	5	t	0
641	273	3	t	0
642	274	4	t	0
643	274	2	t	0
644	275	5	t	0
645	275	4	t	0
646	275	8	t	0.299999999999999989
647	276	1	t	0
648	276	2	t	0
649	276	5	t	0.5
650	277	4	t	0
651	277	8	t	0
652	277	5	t	0.299999999999999989
653	278	9	t	0
654	278	6	t	0
655	279	9	t	0
656	279	4	t	0.25
657	279	7	t	0.299999999999999989
658	280	3	t	0
659	280	2	t	0
660	281	1	t	0
661	281	2	t	0
662	281	3	t	0.299999999999999989
663	282	6	t	0
664	282	5	t	0
665	283	2	t	0
666	283	3	t	0
667	284	6	t	0
668	284	3	t	0
669	285	9	t	0
670	285	5	t	0
671	286	5	t	0
672	286	4	t	0
673	286	9	t	0.299999999999999989
674	287	4	t	0
675	287	6	t	0
676	288	1	t	0
677	288	5	t	0.25
678	288	6	t	0.299999999999999989
679	289	3	t	0
680	289	6	t	0
681	289	7	t	0.299999999999999989
682	290	3	t	0
683	290	1	t	0
684	291	5	t	0
685	291	8	t	0
686	291	3	t	0.299999999999999989
687	292	6	t	0
688	292	8	t	0
689	293	1	t	0
690	293	8	t	0
691	294	8	t	0
692	294	6	t	0.25
693	295	3	t	0
694	295	1	t	0.25
695	295	9	t	0.299999999999999989
696	296	9	t	0
697	296	2	t	0.25
698	297	4	t	0
699	297	5	t	0
700	298	2	t	0
701	298	3	t	0
702	298	4	t	0.299999999999999989
703	299	9	t	0
704	299	4	t	0
705	299	5	t	0.299999999999999989
706	300	1	t	0
707	300	3	t	0
708	301	9	t	0
709	301	1	t	0
710	301	7	t	0.299999999999999989
711	302	6	t	0
712	302	2	t	0
713	302	8	t	0.299999999999999989
714	303	4	t	0
715	303	3	t	0
716	303	6	t	0.299999999999999989
717	304	3	t	0
718	304	7	t	0
719	304	9	t	0.299999999999999989
720	305	4	t	0
721	305	5	t	0
722	305	2	t	0.299999999999999989
723	306	4	t	0
724	306	7	t	0.25
725	307	3	t	0
726	307	5	t	0
727	307	2	t	0.299999999999999989
728	308	8	t	0
729	308	3	t	0.25
730	309	9	t	0
731	309	3	t	0
732	310	8	t	0
733	310	5	t	0
734	311	4	t	0
735	311	3	t	0
736	312	5	t	0
737	312	8	t	0.25
738	313	9	t	0
739	313	7	t	0.25
740	313	1	t	0.299999999999999989
741	314	8	t	0
742	314	5	t	0
743	315	9	t	0
744	315	1	t	0
745	316	6	t	0
746	316	3	t	0
747	316	9	t	0.299999999999999989
748	317	6	t	0
749	317	4	t	0.25
750	318	8	t	0
751	318	3	t	0
752	319	2	t	0
753	319	4	t	0
754	319	9	t	0.299999999999999989
755	320	4	t	0
756	320	6	t	0
757	321	7	t	0
758	321	3	t	0
759	322	3	t	0
760	322	8	t	0.25
761	323	5	t	0
762	323	6	t	0
763	324	8	t	0
764	324	6	t	0
765	325	8	t	0
766	325	4	t	0.25
767	326	6	t	0
768	326	8	t	0
769	326	9	t	0.299999999999999989
770	327	1	t	0
771	327	9	t	0
772	328	5	t	0
773	328	1	t	0.25
774	329	2	t	0
775	329	1	t	0
776	330	3	t	0
777	330	4	t	0
778	330	9	t	0.299999999999999989
779	331	3	t	0
780	331	6	t	0
781	332	8	t	0
782	332	5	t	0
783	333	7	t	0
784	333	1	t	0
785	334	4	t	0
786	334	9	t	0
787	334	7	t	0.299999999999999989
788	335	8	t	0
789	335	7	t	0
790	336	4	t	0
791	336	6	t	0
792	337	3	t	0
793	337	4	t	0
794	338	5	t	0
795	338	2	t	0.25
796	339	5	t	0
797	339	6	t	0
798	340	5	t	0
799	340	7	t	0
800	341	6	t	0
801	341	2	t	0
802	341	9	t	0.299999999999999989
803	342	8	t	0
804	342	3	t	0
805	343	4	t	0
806	343	5	t	0
807	344	4	t	0
808	344	8	t	0
809	345	7	t	0
810	345	5	t	0.25
811	346	6	t	0
812	346	4	t	0
813	347	8	t	0
814	347	3	t	0
815	348	8	t	0
816	348	9	t	0
817	348	7	t	0.299999999999999989
818	349	3	t	0
819	349	9	t	0
820	350	3	t	0
821	350	7	t	0
822	351	5	t	0
823	351	1	t	0
824	352	9	t	0
825	352	7	t	0
826	353	5	t	0
827	353	1	t	0
828	353	4	t	0.299999999999999989
829	354	7	t	0
830	354	4	t	0
831	354	3	t	0.299999999999999989
832	355	4	t	0
833	355	1	t	0.25
834	356	3	t	0
835	356	8	t	0
836	357	2	t	0
837	357	1	t	0
838	357	8	t	0.299999999999999989
839	358	5	t	0
840	358	8	t	0
841	359	2	t	0
842	359	8	t	0
843	359	1	t	0.5
844	360	1	t	0
845	360	7	t	0
846	361	9	t	0
847	361	6	t	0
848	362	7	t	0
849	362	3	t	0
850	363	1	t	0
851	363	6	t	0
852	363	3	t	0.5
853	364	4	t	0
854	364	3	t	0.25
855	364	7	t	0.299999999999999989
856	365	7	t	0
857	365	1	t	0.25
858	366	3	t	0
859	366	9	t	0
860	367	6	t	0
861	367	2	t	0
862	368	8	t	0
863	368	7	t	0.25
864	368	2	t	0.299999999999999989
865	369	2	t	0
866	369	7	t	0
867	370	7	t	0
868	370	8	t	0
869	371	8	t	0
870	371	3	t	0
871	371	4	t	0.299999999999999989
872	372	4	t	0
873	372	3	t	0.25
874	372	9	t	0.299999999999999989
875	373	9	t	0
876	373	1	t	0
877	374	8	t	0
878	374	5	t	0
879	374	1	t	0.299999999999999989
880	375	2	t	0
881	375	5	t	0
882	376	4	t	0
883	376	3	t	0
884	377	3	t	0
885	377	8	t	0
886	377	2	t	0.299999999999999989
887	378	9	t	0
888	378	4	t	0
889	379	1	t	0
890	379	6	t	0
891	380	6	t	0
892	380	8	t	0
893	380	5	t	0.299999999999999989
894	381	1	t	0
895	381	3	t	0
896	381	5	t	0.299999999999999989
897	382	3	t	0
898	382	8	t	0
899	382	7	t	0.299999999999999989
900	383	9	t	0
901	383	4	t	0
902	384	3	t	0
903	384	2	t	0
904	384	6	t	0.299999999999999989
905	385	7	t	0
906	385	1	t	0
907	386	2	t	0
908	386	7	t	0.25
909	387	3	t	0
910	387	8	t	0
911	388	7	t	0
912	388	8	t	0
913	388	4	t	0.299999999999999989
914	389	2	t	0
915	389	3	t	0.25
916	390	6	t	0
917	390	3	t	0
918	391	2	t	0
919	391	5	t	0.25
920	391	1	t	0.5
921	392	1	t	0
922	392	7	t	0
923	392	9	t	0.299999999999999989
924	393	2	t	0
925	393	7	t	0
926	393	3	t	0.299999999999999989
927	394	6	t	0
928	394	7	t	0
929	394	1	t	0.299999999999999989
930	395	2	t	0
931	395	1	t	0
932	395	3	t	0.299999999999999989
933	396	3	t	0
934	396	6	t	0
935	396	8	t	0.299999999999999989
936	397	6	t	0
937	397	5	t	0
938	398	6	t	0
939	398	4	t	0
940	399	3	t	0
941	399	8	t	0
942	400	3	t	0
943	400	6	t	0
944	400	4	t	0.299999999999999989
945	401	3	t	0
946	401	9	t	0
947	402	3	t	0
948	402	7	t	0
949	402	5	t	0.299999999999999989
950	403	9	t	0
951	403	2	t	0
952	404	1	t	0
953	404	7	t	0
954	405	2	t	0
955	405	7	t	0
956	406	9	t	0
957	406	7	t	0
958	407	4	t	0
959	407	8	t	0.25
960	408	2	t	0
961	408	1	t	0
962	409	9	t	0
963	409	1	t	0
964	410	2	t	0
965	410	6	t	0
966	411	7	t	0
967	411	1	t	0
968	411	2	t	0.299999999999999989
969	412	5	t	0
970	412	1	t	0.25
971	412	7	t	0.299999999999999989
972	413	6	t	0
973	413	7	t	0
974	414	8	t	0
975	414	9	t	0
976	414	4	t	0.299999999999999989
977	415	6	t	0
978	415	9	t	0
979	416	9	t	0
980	416	2	t	0
981	417	3	t	0
982	417	6	t	0
983	418	5	t	0
984	418	4	t	0
985	419	1	t	0
986	419	4	t	0.25
987	419	5	t	0.299999999999999989
988	420	9	t	0
989	420	5	t	0.25
990	421	5	t	0
991	421	2	t	0
992	422	8	t	0
993	422	7	t	0.25
994	422	4	t	0.299999999999999989
995	423	8	t	0
996	423	3	t	0
997	424	6	t	0
998	424	2	t	0
999	425	2	t	0
1000	425	7	t	0
1001	426	9	t	0
1002	426	3	t	0
1003	427	3	t	0
1004	427	1	t	0
1005	427	7	t	0.5
1006	428	8	t	0
1007	428	6	t	0
1008	429	6	t	0
1009	429	2	t	0
1010	429	8	t	0.299999999999999989
1011	430	3	t	0
1012	430	9	t	0
1013	431	4	t	0
1014	431	6	t	0
1015	432	1	t	0
1016	432	2	t	0
1017	433	6	t	0
1018	433	3	t	0
1019	433	1	t	0.299999999999999989
1020	434	2	t	0
1021	434	9	t	0
1022	435	5	t	0
1023	435	1	t	0
1024	436	7	t	0
1025	436	6	t	0
1026	437	8	t	0
1027	437	3	t	0
1028	437	6	t	0.299999999999999989
1029	438	2	t	0
1030	438	3	t	0
1031	439	6	t	0
1032	439	4	t	0
1033	440	8	t	0
1034	440	7	t	0
1035	440	9	t	0.299999999999999989
1036	441	3	t	0
1037	441	7	t	0.25
1038	441	4	t	0.5
1039	442	7	t	0
1040	442	8	t	0.25
1041	443	6	t	0
1042	443	4	t	0.25
1043	444	4	t	0
1044	444	1	t	0.25
1045	445	2	t	0
1046	445	8	t	0
1047	446	4	t	0
1048	446	3	t	0
1049	447	4	t	0
1050	447	6	t	0
1051	448	4	t	0
1052	448	5	t	0
1053	449	8	t	0
1054	449	1	t	0
1055	450	1	t	0
1056	450	7	t	0
1057	451	3	t	0
1058	451	5	t	0.25
1059	452	3	t	0
1060	452	9	t	0
1061	452	4	t	0.299999999999999989
1062	453	7	t	0
1063	453	4	t	0
1064	454	8	t	0
1065	454	4	t	0
1066	454	5	t	0.299999999999999989
1067	455	3	t	0
1068	455	6	t	0
1069	456	5	t	0
1070	456	9	t	0
1071	456	2	t	0.299999999999999989
1072	457	3	t	0
1073	457	5	t	0.25
1074	458	4	t	0
1075	458	5	t	0
1076	459	8	t	0
1077	459	1	t	0
1078	460	6	t	0
1079	460	4	t	0
1080	461	1	t	0
1081	461	7	t	0
1082	461	3	t	0.299999999999999989
1083	462	8	t	0
1084	462	2	t	0
1085	463	7	t	0
1086	463	4	t	0
1087	463	5	t	0.299999999999999989
1088	464	8	t	0
1089	464	5	t	0
1090	464	3	t	0.5
1091	465	4	t	0
1092	465	5	t	0.25
1093	466	4	t	0
1094	466	9	t	0
1095	466	6	t	0.299999999999999989
1096	467	7	t	0
1097	467	5	t	0.25
1098	468	7	t	0
1099	468	5	t	0
1100	469	4	t	0
1101	469	8	t	0
1102	469	1	t	0.299999999999999989
1103	470	4	t	0
1104	470	1	t	0
1105	470	2	t	0.299999999999999989
1106	471	8	t	0
1107	471	6	t	0
1108	472	9	t	0
1109	472	6	t	0
1110	473	7	t	0
1111	473	3	t	0
1112	473	1	t	0.299999999999999989
1113	474	5	t	0
1114	474	1	t	0
1115	474	9	t	0.299999999999999989
1116	475	9	t	0
1117	475	3	t	0.25
1118	476	5	t	0
1119	476	9	t	0.25
1120	477	2	t	0
1121	477	7	t	0
1122	478	7	t	0
1123	478	8	t	0
1124	478	2	t	0.5
1125	479	8	t	0
1126	479	3	t	0
1127	480	7	t	0
1128	480	4	t	0
1129	481	7	t	0
1130	481	4	t	0
1131	482	4	t	0
1132	482	1	t	0
1133	483	1	t	0
1134	483	3	t	0
1135	484	8	t	0
1136	484	7	t	0.25
1137	484	5	t	0.299999999999999989
1138	485	7	t	0
1139	485	8	t	0
1140	486	3	t	0
1141	486	5	t	0
1142	487	2	t	0
1143	487	3	t	0
1144	487	4	t	0.299999999999999989
1145	488	8	t	0
1146	488	2	t	0
1147	489	5	t	0
1148	489	2	t	0
1149	489	7	t	0.299999999999999989
1150	490	1	t	0
1151	490	4	t	0
1152	491	8	t	0
1153	491	3	t	0.25
1154	492	5	t	0
1155	492	4	t	0
1156	492	3	t	0.299999999999999989
1157	493	8	t	0
1158	493	6	t	0.25
1159	494	1	t	0
1160	494	7	t	0
1161	495	2	t	0
1162	495	6	t	0
1163	495	3	t	0.299999999999999989
1164	496	4	t	0
1165	496	7	t	0
1166	496	8	t	0.299999999999999989
1167	497	3	t	0
1168	497	2	t	0
1169	498	1	t	0
1170	498	3	t	0
1171	498	8	t	0.5
1172	499	8	t	0
1173	499	3	t	0
1174	500	5	t	0
1175	500	7	t	0
1176	501	8	t	0
1177	501	2	t	0
1178	502	5	t	0
1179	502	9	t	0
1180	503	1	t	0
1181	503	8	t	0
1182	504	9	t	0
1183	504	4	t	0.25
1184	505	3	t	0
1185	505	9	t	0
1186	506	2	t	0
1187	506	9	t	0
1188	507	8	t	0
1189	507	1	t	0
1190	507	3	t	0.299999999999999989
1191	508	7	t	0
1192	508	4	t	0
1193	509	7	t	0
1194	509	5	t	0
1195	509	2	t	0.299999999999999989
1196	510	5	t	0
1197	510	2	t	0
1198	510	8	t	0.299999999999999989
1199	511	8	t	0
1200	511	4	t	0
1201	512	9	t	0
1202	512	3	t	0
1203	513	2	t	0
1204	513	6	t	0
1205	514	1	t	0
1206	514	6	t	0
1207	515	7	t	0
1208	515	8	t	0
1209	516	6	t	0
1210	516	5	t	0
1211	517	3	t	0
1212	517	6	t	0
1213	518	2	t	0
1214	518	1	t	0
1215	519	7	t	0
1216	519	2	t	0
1217	520	4	t	0
1218	520	8	t	0
1219	521	1	t	0
1220	521	3	t	0.25
1221	521	9	t	0.299999999999999989
1222	522	3	t	0
1223	522	5	t	0
1224	522	1	t	0.299999999999999989
1225	523	7	t	0
1226	523	4	t	0
1227	523	5	t	0.299999999999999989
1228	524	6	t	0
1229	524	4	t	0
1230	524	9	t	0.299999999999999989
1231	525	2	t	0
1232	525	5	t	0
1233	526	6	t	0
1234	526	2	t	0
1235	527	6	t	0
1236	527	9	t	0
1237	527	1	t	0.5
1238	528	8	t	0
1239	528	3	t	0
1240	529	8	t	0
1241	529	4	t	0
1242	529	9	t	0.299999999999999989
1243	530	7	t	0
1244	530	1	t	0
1245	531	3	t	0
1246	531	5	t	0
1247	532	3	t	0
1248	532	7	t	0
1249	533	6	t	0
1250	533	2	t	0
1251	534	1	t	0
1252	534	9	t	0
1253	535	4	t	0
1254	535	9	t	0
1255	536	4	t	0
1256	536	5	t	0
1257	537	3	t	0
1258	537	1	t	0
1259	538	2	t	0
1260	538	7	t	0
1261	539	1	t	0
1262	539	8	t	0
1263	540	4	t	0
1264	540	2	t	0
1265	541	2	t	0
1266	541	3	t	0
1267	542	9	t	0
1268	542	2	t	0
1269	543	9	t	0
1270	543	8	t	0
1271	544	9	t	0
1272	544	6	t	0.25
1273	545	2	t	0
1274	545	5	t	0
1275	546	9	t	0
1276	546	3	t	0
1277	547	2	t	0
1278	547	9	t	0
1279	548	5	t	0
1280	548	7	t	0
1281	549	4	t	0
1282	549	9	t	0
1283	550	6	t	0
1284	550	2	t	0
1285	551	2	t	0
1286	551	5	t	0
1287	552	1	t	0
1288	552	7	t	0
1289	553	3	t	0
1290	553	9	t	0
1291	554	6	t	0
1292	554	1	t	0
1293	554	7	t	0.5
1294	555	2	t	0
1295	555	1	t	0
1296	556	8	t	0
1297	556	7	t	0
1298	557	8	t	0
1299	557	2	t	0
1300	558	2	t	0
1301	558	1	t	0
1302	559	9	t	0
1303	559	8	t	0
1304	559	7	t	0.299999999999999989
1305	560	8	t	0
1306	560	1	t	0.25
1307	560	3	t	0.299999999999999989
1308	561	6	t	0
1309	561	9	t	0.25
1310	562	9	t	0
1311	562	5	t	0
1312	563	3	t	0
1313	563	7	t	0
1314	564	3	t	0
1315	564	9	t	0
1316	565	6	t	0
1317	565	3	t	0
1318	566	4	t	0
1319	566	5	t	0
1320	567	9	t	0
1321	567	1	t	0
1322	567	5	t	0.299999999999999989
1323	568	9	t	0
1324	568	2	t	0.25
1325	569	2	t	0
1326	569	4	t	0
1327	570	8	t	0
1328	570	4	t	0
1329	571	5	t	0
1330	571	3	t	0
1331	571	1	t	0.299999999999999989
1332	572	1	t	0
1333	572	2	t	0
1334	572	3	t	0.299999999999999989
1335	573	3	t	0
1336	573	8	t	0
1337	574	9	t	0
1338	574	5	t	0
1339	575	7	t	0
1340	575	3	t	0
1341	575	9	t	0.5
1342	576	9	t	0
1343	576	5	t	0
1344	577	7	t	0
1345	577	3	t	0
1346	578	7	t	0
1347	578	4	t	0
1348	579	9	t	0
1349	579	2	t	0
1350	580	9	t	0
1351	580	1	t	0
1352	581	8	t	0
1353	581	2	t	0
1354	582	9	t	0
1355	582	4	t	0
1356	583	9	t	0
1357	583	8	t	0
1358	584	3	t	0
1359	584	7	t	0
1360	584	2	t	0.299999999999999989
1361	585	8	t	0
1362	585	1	t	0.25
1363	585	4	t	0.299999999999999989
1364	586	3	t	0
1365	586	4	t	0
1366	586	1	t	0.299999999999999989
1367	587	3	t	0
1368	587	9	t	0
1369	587	8	t	0.299999999999999989
1370	588	7	t	0
1371	588	1	t	0
1372	588	4	t	0.299999999999999989
1373	589	4	t	0
1374	589	1	t	0.25
1375	589	3	t	0.299999999999999989
1376	590	1	t	0
1377	590	2	t	0
1378	591	8	t	0
1379	591	9	t	0
1380	592	1	t	0
1381	592	6	t	0
1382	593	3	t	0
1383	593	9	t	0
1384	594	7	t	0
1385	594	8	t	0
1386	595	5	t	0
1387	595	9	t	0
1388	595	8	t	0.299999999999999989
1389	596	6	t	0
1390	596	4	t	0
1391	597	3	t	0
1392	597	2	t	0
1393	598	1	t	0
1394	598	6	t	0.25
1395	599	2	t	0
1396	599	9	t	0.25
1397	599	6	t	0.299999999999999989
1398	600	9	t	0
1399	600	7	t	0
1400	601	8	t	0
1401	601	3	t	0
1402	601	9	t	0.299999999999999989
1403	602	3	t	0
1404	602	1	t	0.25
1405	602	5	t	0.299999999999999989
1406	603	3	t	0
1407	603	6	t	0
1408	604	4	t	0
1409	604	5	t	0
1410	605	4	t	0
1411	605	5	t	0
1412	606	1	t	0
1413	606	8	t	0.25
1414	606	2	t	0.299999999999999989
1415	607	7	t	0
1416	607	3	t	0.25
1417	607	4	t	0.5
1418	608	7	t	0
1419	608	9	t	0
1420	609	2	t	0
1421	609	9	t	0
1422	610	9	t	0
1423	610	3	t	0
1424	611	3	t	0
1425	611	9	t	0.25
1426	611	6	t	0.299999999999999989
1427	612	8	t	0
1428	612	9	t	0
1429	613	5	t	0
1430	613	8	t	0
1431	613	4	t	0.299999999999999989
1432	614	9	t	0
1433	614	7	t	0
1434	614	4	t	0.299999999999999989
1435	615	8	t	0
1436	615	9	t	0
1437	615	5	t	0.299999999999999989
1438	616	8	t	0
1439	616	1	t	0
1440	617	7	t	0
1441	617	8	t	0
1442	618	4	t	0
1443	618	3	t	0
1444	618	1	t	0.299999999999999989
1445	619	2	t	0
1446	619	7	t	0
1447	619	5	t	0.299999999999999989
1448	620	3	t	0
1449	620	6	t	0
1450	621	7	t	0
1451	621	1	t	0
1452	622	5	t	0
1453	622	2	t	0.25
1454	623	6	t	0
1455	623	3	t	0
1456	624	8	t	0
1457	624	4	t	0
1458	625	7	t	0
1459	625	8	t	0
1460	626	6	t	0
1461	626	2	t	0
1462	627	3	t	0
1463	627	1	t	0
1464	628	7	t	0
1465	628	6	t	0.25
1466	629	6	t	0
1467	629	2	t	0
1468	630	8	t	0
1469	630	2	t	0
1470	631	8	t	0
1471	631	3	t	0
1472	631	7	t	0.299999999999999989
1473	632	2	t	0
1474	632	3	t	0
1475	632	5	t	0.299999999999999989
1476	633	5	t	0
1477	633	8	t	0
1478	634	9	t	0
1479	634	7	t	0
1480	634	3	t	0.299999999999999989
1481	635	2	t	0
1482	635	9	t	0
1483	636	5	t	0
1484	636	1	t	0
1485	636	6	t	0.299999999999999989
1486	637	8	t	0
1487	637	7	t	0.25
1488	638	8	t	0
1489	638	5	t	0
1490	638	1	t	0.299999999999999989
1491	639	4	t	0
1492	639	6	t	0
1493	640	6	t	0
1494	640	4	t	0
1495	641	3	t	0
1496	641	8	t	0
1497	642	9	t	0
1498	642	5	t	0
1499	642	3	t	0.299999999999999989
1500	643	4	t	0
1501	643	6	t	0
1502	643	1	t	0.299999999999999989
1503	644	9	t	0
1504	644	6	t	0.25
1505	645	5	t	0
1506	645	2	t	0
1507	646	2	t	0
1508	646	7	t	0
1509	647	7	t	0
1510	647	6	t	0
1511	648	5	t	0
1512	648	8	t	0
1513	648	7	t	0.299999999999999989
1514	649	9	t	0
1515	649	7	t	0
1516	650	1	t	0
1517	650	8	t	0
1518	651	8	t	0
1519	651	7	t	0
1520	652	5	t	0
1521	652	4	t	0.25
1522	652	8	t	0.299999999999999989
1523	653	8	t	0
1524	653	4	t	0
1525	654	3	t	0
1526	654	9	t	0
1527	655	4	t	0
1528	655	5	t	0
1529	656	5	t	0
1530	656	7	t	0
1531	657	7	t	0
1532	657	3	t	0
1533	657	2	t	0.299999999999999989
1534	658	8	t	0
1535	658	2	t	0
1536	658	5	t	0.299999999999999989
1537	659	5	t	0
1538	659	7	t	0
1539	659	8	t	0.299999999999999989
1540	660	5	t	0
1541	660	1	t	0.25
1542	660	6	t	0.299999999999999989
1543	661	3	t	0
1544	661	2	t	0
1545	662	5	t	0
1546	662	2	t	0
1547	662	6	t	0.299999999999999989
1548	663	6	t	0
1549	663	1	t	0
1550	664	3	t	0
1551	664	4	t	0
1552	665	9	t	0
1553	665	1	t	0
1554	666	4	t	0
1555	666	8	t	0
1556	667	7	t	0
1557	667	2	t	0
1558	668	2	t	0
1559	668	4	t	0
1560	669	1	t	0
1561	669	2	t	0
1562	670	9	t	0
1563	670	2	t	0
1564	670	4	t	0.299999999999999989
1565	671	7	t	0
1566	671	6	t	0
1567	672	9	t	0
1568	672	8	t	0
1569	672	2	t	0.299999999999999989
1570	673	1	t	0
1571	673	6	t	0
1572	674	4	t	0
1573	674	7	t	0
1574	675	9	t	0
1575	675	1	t	0
1576	675	6	t	0.299999999999999989
1577	676	3	t	0
1578	676	5	t	0
1579	677	2	t	0
1580	677	4	t	0
1581	678	8	t	0
1582	678	7	t	0
1583	679	3	t	0
1584	679	4	t	0
1585	679	1	t	0.299999999999999989
1586	680	4	t	0
1587	680	5	t	0
1588	681	7	t	0
1589	681	9	t	0
1590	681	4	t	0.299999999999999989
1591	682	1	t	0
1592	682	9	t	0
1593	682	2	t	0.299999999999999989
1594	683	9	t	0
1595	683	2	t	0.25
1596	684	4	t	0
1597	684	2	t	0
1598	685	7	t	0
1599	685	6	t	0
1600	686	7	t	0
1601	686	1	t	0
1602	687	8	t	0
1603	687	2	t	0.25
1604	687	3	t	0.299999999999999989
1605	688	2	t	0
1606	688	9	t	0
1607	689	9	t	0
1608	689	3	t	0
1609	689	8	t	0.299999999999999989
1610	690	8	t	0
1611	690	3	t	0
1612	690	1	t	0.299999999999999989
1613	691	4	t	0
1614	691	1	t	0
1615	692	9	t	0
1616	692	7	t	0
1617	693	3	t	0
1618	693	6	t	0
1619	694	7	t	0
1620	694	3	t	0
1621	695	5	t	0
1622	695	9	t	0
1623	696	3	t	0
1624	696	2	t	0
1625	697	1	t	0
1626	697	6	t	0
1627	698	7	t	0
1628	698	2	t	0
1629	699	4	t	0
1630	699	7	t	0
1631	699	5	t	0.299999999999999989
1632	700	6	t	0
1633	700	2	t	0
1634	700	4	t	0.299999999999999989
1635	701	3	t	0
1636	701	1	t	0
1637	702	6	t	0
1638	702	5	t	0
1639	703	1	t	0
1640	703	9	t	0
1641	703	5	t	0.299999999999999989
1642	704	1	t	0
1643	704	6	t	0
1644	705	1	t	0
1645	705	4	t	0
1646	706	4	t	0
1647	706	5	t	0
1648	707	7	t	0
1649	707	2	t	0
1650	708	4	t	0
1651	708	9	t	0
1652	709	3	t	0
1653	709	4	t	0
1654	709	6	t	0.5
1655	710	4	t	0
1656	710	6	t	0
1657	711	1	t	0
1658	711	3	t	0
1659	711	8	t	0.299999999999999989
1660	712	9	t	0
1661	712	4	t	0
1662	713	4	t	0
1663	713	6	t	0.25
1664	714	1	t	0
1665	714	4	t	0
1666	715	5	t	0
1667	715	7	t	0
1668	715	6	t	0.299999999999999989
1669	716	3	t	0
1670	716	7	t	0
1671	716	9	t	0.299999999999999989
1672	717	5	t	0
1673	717	7	t	0
1674	717	9	t	0.299999999999999989
1675	718	4	t	0
1676	718	5	t	0
1677	718	1	t	0.299999999999999989
1678	719	5	t	0
1679	719	9	t	0
1680	720	5	t	0
1681	720	9	t	0
1682	721	6	t	0
1683	721	7	t	0
1684	722	3	t	0
1685	722	2	t	0
1686	722	7	t	0.299999999999999989
1687	723	4	t	0
1688	723	6	t	0.25
1689	723	5	t	0.299999999999999989
1690	724	7	t	0
1691	724	3	t	0
1692	725	8	t	0
1693	725	3	t	0
1694	725	2	t	0.299999999999999989
1695	726	8	t	0
1696	726	2	t	0
1697	727	7	t	0
1698	727	5	t	0
1699	728	7	t	0
1700	728	4	t	0
1701	729	6	t	0
1702	729	4	t	0
1703	730	3	t	0
1704	730	2	t	0
1705	731	6	t	0
1706	731	8	t	0
1707	731	2	t	0.5
1708	732	6	t	0
1709	732	5	t	0
1710	733	6	t	0
1711	733	5	t	0
1712	734	1	t	0
1713	734	7	t	0.25
1714	734	8	t	0.299999999999999989
1715	735	3	t	0
1716	735	7	t	0.25
1717	736	8	t	0
1718	736	4	t	0
1719	737	6	t	0
1720	737	5	t	0
1721	738	7	t	0
1722	738	9	t	0
1723	739	2	t	0
1724	739	3	t	0.25
1725	740	3	t	0
1726	740	9	t	0
1727	741	3	t	0
1728	741	4	t	0.25
1729	742	7	t	0
1730	742	2	t	0.25
1731	743	2	t	0
1732	743	7	t	0
1733	744	9	t	0
1734	744	5	t	0
1735	745	8	t	0
1736	745	7	t	0
1737	746	6	t	0
1738	746	4	t	0
1739	747	6	t	0
1740	747	1	t	0
1741	748	2	t	0
1742	748	5	t	0
1743	748	1	t	0.299999999999999989
1744	749	4	t	0
1745	749	5	t	0
1746	749	3	t	0.299999999999999989
1747	750	5	t	0
1748	750	9	t	0
1749	751	6	t	0
1750	751	9	t	0
1751	752	3	t	0
1752	752	8	t	0
1753	753	7	t	0
1754	753	6	t	0
1755	754	5	t	0
1756	754	1	t	0
1757	755	8	t	0
1758	755	4	t	0
1759	756	1	t	0
1760	756	2	t	0
1761	757	7	t	0
1762	757	1	t	0
1763	758	1	t	0
1764	758	3	t	0
1765	759	7	t	0
1766	759	4	t	0
1767	759	3	t	0.299999999999999989
1768	760	3	t	0
1769	760	2	t	0.25
1770	761	3	t	0
1771	761	8	t	0
1772	761	5	t	0.299999999999999989
1773	762	6	t	0
1774	762	3	t	0
1775	763	7	t	0
1776	763	8	t	0
1777	764	4	t	0
1778	764	5	t	0
1779	765	5	t	0
1780	765	8	t	0
1781	766	7	t	0
1782	766	1	t	0
1783	767	6	t	0
1784	767	3	t	0
1785	768	9	t	0
1786	768	4	t	0
1787	769	1	t	0
1788	769	2	t	0
1789	769	5	t	0.299999999999999989
1790	770	3	t	0
1791	770	8	t	0
1792	771	5	t	0
1793	771	2	t	0
1794	772	1	t	0
1795	772	9	t	0
1796	772	5	t	0.299999999999999989
1797	773	3	t	0
1798	773	7	t	0
1799	773	2	t	0.5
1800	774	6	t	0
1801	774	3	t	0.25
1802	775	7	t	0
1803	775	4	t	0
1804	775	6	t	0.299999999999999989
1805	776	5	t	0
1806	776	4	t	0
1807	777	5	t	0
1808	777	9	t	0
1809	778	1	t	0
1810	778	9	t	0
1811	779	8	t	0
1812	779	9	t	0
1813	780	2	t	0
1814	780	6	t	0
1815	781	5	t	0
1816	781	7	t	0.25
1817	782	1	t	0
1818	782	2	t	0
1819	783	4	t	0
1820	783	9	t	0
1821	783	7	t	0.299999999999999989
1822	784	3	t	0
1823	784	9	t	0
1824	785	9	t	0
1825	785	4	t	0
1826	786	8	t	0
1827	786	4	t	0
1828	786	5	t	0.299999999999999989
1829	787	6	t	0
1830	787	5	t	0
1831	788	2	t	0
1832	788	4	t	0
1833	789	3	t	0
1834	789	4	t	0
1835	789	6	t	0.299999999999999989
1836	790	4	t	0
1837	790	1	t	0.25
1838	791	7	t	0
1839	791	6	t	0
1840	792	3	t	0
1841	792	1	t	0
1842	793	3	t	0
1843	793	9	t	0.25
1844	794	3	t	0
1845	794	2	t	0
1846	794	1	t	0.299999999999999989
1847	795	5	t	0
1848	795	8	t	0.25
1849	796	7	t	0
1850	796	5	t	0
1851	796	3	t	0.299999999999999989
1852	797	9	t	0
1853	797	6	t	0
1854	798	2	t	0
1855	798	9	t	0
1856	799	7	t	0
1857	799	6	t	0.25
1858	799	8	t	0.299999999999999989
1859	800	1	t	0
1860	800	5	t	0
1861	800	4	t	0.299999999999999989
1862	801	3	t	0
1863	801	6	t	0
1864	802	1	t	0
1865	802	6	t	0.25
1866	803	7	t	0
1867	803	6	t	0
1868	804	6	t	0
1869	804	7	t	0
1870	805	6	t	0
1871	805	4	t	0
1872	806	2	t	0
1873	806	3	t	0
1874	807	9	t	0
1875	807	2	t	0
1876	808	5	t	0
1877	808	7	t	0
1878	809	4	t	0
1879	809	3	t	0
1880	810	1	t	0
1881	810	5	t	0
1882	810	2	t	0.299999999999999989
1883	811	6	t	0
1884	811	1	t	0
1885	812	4	t	0
1886	812	8	t	0.25
1887	813	2	t	0
1888	813	6	t	0
1889	814	5	t	0
1890	814	6	t	0
1891	814	4	t	0.299999999999999989
1892	815	5	t	0
1893	815	6	t	0
1894	816	9	t	0
1895	816	2	t	0
1896	816	3	t	0.299999999999999989
1897	817	1	t	0
1898	817	6	t	0
1899	817	2	t	0.5
1900	818	5	t	0
1901	818	8	t	0
1902	818	4	t	0.299999999999999989
1903	819	3	t	0
1904	819	8	t	0
1905	820	6	t	0
1906	820	2	t	0
1907	820	5	t	0.299999999999999989
1908	821	8	t	0
1909	821	1	t	0
1910	822	4	t	0
1911	822	6	t	0
1912	823	7	t	0
1913	823	3	t	0
1914	824	4	t	0
1915	824	1	t	0
1916	824	5	t	0.299999999999999989
1917	825	3	t	0
1918	825	4	t	0
1919	825	8	t	0.299999999999999989
1920	826	5	t	0
1921	826	8	t	0
1922	827	9	t	0
1923	827	3	t	0
1924	828	6	t	0
1925	828	7	t	0
1926	828	5	t	0.299999999999999989
1927	829	8	t	0
1928	829	5	t	0
1929	830	2	t	0
1930	830	8	t	0
1931	831	4	t	0
1932	831	6	t	0
1933	832	4	t	0
1934	832	3	t	0
1935	833	9	t	0
1936	833	6	t	0
1937	833	2	t	0.299999999999999989
1938	834	1	t	0
1939	834	3	t	0
1940	835	3	t	0
1941	835	8	t	0
1942	836	5	t	0
1943	836	9	t	0
1944	837	4	t	0
1945	837	2	t	0
1946	838	5	t	0
1947	838	7	t	0
1948	839	5	t	0
1949	839	7	t	0
1950	840	1	t	0
1951	840	3	t	0
1952	840	8	t	0.299999999999999989
1953	841	9	t	0
1954	841	4	t	0
1955	841	8	t	0.299999999999999989
1956	842	1	t	0
1957	842	8	t	0
1958	842	6	t	0.5
1959	843	2	t	0
1960	843	8	t	0
1961	844	9	t	0
1962	844	1	t	0.25
1963	845	4	t	0
1964	845	8	t	0
1965	846	3	t	0
1966	846	8	t	0
1967	847	1	t	0
1968	847	7	t	0.25
1969	848	5	t	0
1970	848	1	t	0
1971	848	9	t	0.299999999999999989
1972	849	2	t	0
1973	849	3	t	0
1974	850	1	t	0
1975	850	5	t	0
1976	851	6	t	0
1977	851	5	t	0
1978	852	1	t	0
1979	852	5	t	0
1980	852	8	t	0.299999999999999989
1981	853	9	t	0
1982	853	2	t	0.25
1983	853	6	t	0.299999999999999989
1984	854	6	t	0
1985	854	1	t	0
1986	854	2	t	0.299999999999999989
1987	855	1	t	0
1988	855	2	t	0
1989	856	8	t	0
1990	856	6	t	0
1991	857	4	t	0
1992	857	6	t	0.25
1993	858	8	t	0
1994	858	7	t	0
1995	858	4	t	0.299999999999999989
1996	859	3	t	0
1997	859	9	t	0
1998	860	1	t	0
1999	860	4	t	0
2000	861	9	t	0
2001	861	2	t	0
2002	861	4	t	0.299999999999999989
2003	862	6	t	0
2004	862	9	t	0
2005	863	7	t	0
2006	863	3	t	0
2007	864	8	t	0
2008	864	7	t	0
2009	865	3	t	0
2010	865	2	t	0.25
2011	866	6	t	0
2012	866	7	t	0.25
2013	867	1	t	0
2014	867	9	t	0
2015	868	4	t	0
2016	868	6	t	0.25
2017	869	1	t	0
2018	869	4	t	0
2019	870	4	t	0
2020	870	8	t	0.25
2021	870	6	t	0.299999999999999989
2022	871	1	t	0
2023	871	2	t	0
2024	872	1	t	0
2025	872	5	t	0
2026	872	2	t	0.299999999999999989
2027	873	4	t	0
2028	873	6	t	0
2029	873	7	t	0.299999999999999989
2030	874	3	t	0
2031	874	4	t	0
2032	874	7	t	0.299999999999999989
2033	875	5	t	0
2034	875	1	t	0
2035	876	8	t	0
2036	876	7	t	0
2037	876	9	t	0.299999999999999989
2038	877	4	t	0
2039	877	1	t	0
2040	878	7	t	0
2041	878	3	t	0
2042	878	9	t	0.299999999999999989
2043	879	1	t	0
2044	879	3	t	0
2045	880	8	t	0
2046	880	5	t	0
2047	881	2	t	0
2048	881	6	t	0
2049	881	4	t	0.299999999999999989
2050	882	7	t	0
2051	882	6	t	0
2052	883	5	t	0
2053	883	2	t	0
2054	883	4	t	0.299999999999999989
2055	884	3	t	0
2056	884	7	t	0
2057	884	8	t	0.5
2058	885	3	t	0
2059	885	5	t	0
2060	886	8	t	0
2061	886	2	t	0
2062	887	5	t	0
2063	887	3	t	0
2064	888	3	t	0
2065	888	8	t	0.25
2066	888	2	t	0.299999999999999989
2067	889	6	t	0
2068	889	5	t	0
2069	890	8	t	0
2070	890	4	t	0
2071	890	6	t	0.299999999999999989
2072	891	4	t	0
2073	891	2	t	0
2074	892	2	t	0
2075	892	8	t	0
2076	893	9	t	0
2077	893	8	t	0
2078	893	7	t	0.299999999999999989
2079	894	9	t	0
2080	894	7	t	0.25
2081	895	1	t	0
2082	895	4	t	0
2083	895	8	t	0.299999999999999989
2084	896	7	t	0
2085	896	3	t	0
2086	896	6	t	0.299999999999999989
2087	897	9	t	0
2088	897	7	t	0
2089	898	4	t	0
2090	898	8	t	0
2091	899	7	t	0
2092	899	9	t	0
2093	899	2	t	0.299999999999999989
2094	900	3	t	0
2095	900	4	t	0
2096	900	2	t	0.299999999999999989
2097	901	4	t	0
2098	901	7	t	0.25
2099	901	3	t	0.5
2100	902	9	t	0
2101	902	2	t	0
2102	902	7	t	0.299999999999999989
2103	903	2	t	0
2104	903	7	t	0
2105	903	1	t	0.299999999999999989
2106	904	6	t	0
2107	904	2	t	0
2108	905	8	t	0
2109	905	1	t	0
2110	906	3	t	0
2111	906	7	t	0.25
2112	906	5	t	0.299999999999999989
2113	907	1	t	0
2114	907	7	t	0
2115	908	4	t	0
2116	908	3	t	0
2117	909	2	t	0
2118	909	9	t	0
2119	910	7	t	0
2120	910	6	t	0
2121	911	4	t	0
2122	911	5	t	0
2123	911	7	t	0.299999999999999989
2124	912	4	t	0
2125	912	8	t	0
2126	913	4	t	0
2127	913	5	t	0
2128	913	3	t	0.5
2129	914	8	t	0
2130	914	5	t	0.25
2131	915	9	t	0
2132	915	1	t	0
2133	915	3	t	0.299999999999999989
2134	916	2	t	0
2135	916	6	t	0
2136	916	7	t	0.299999999999999989
2137	917	4	t	0
2138	917	1	t	0
2139	918	9	t	0
2140	918	3	t	0
2141	918	6	t	0.299999999999999989
2142	919	8	t	0
2143	919	7	t	0
2144	920	5	t	0
2145	920	3	t	0.25
2146	921	4	t	0
2147	921	6	t	0
2148	921	1	t	0.299999999999999989
2149	922	8	t	0
2150	922	1	t	0
2151	922	3	t	0.299999999999999989
2152	923	2	t	0
2153	923	8	t	0
2154	923	6	t	0.299999999999999989
2155	924	6	t	0
2156	924	3	t	0.25
2157	925	2	t	0
2158	925	5	t	0
2159	926	7	t	0
2160	926	4	t	0
2161	926	6	t	0.5
2162	927	4	t	0
2163	927	6	t	0
2164	927	5	t	0.299999999999999989
2165	928	1	t	0
2166	928	7	t	0
2167	928	2	t	0.299999999999999989
2168	929	3	t	0
2169	929	4	t	0
2170	929	7	t	0.299999999999999989
2171	930	3	t	0
2172	930	4	t	0
2173	931	1	t	0
2174	931	8	t	0
2175	932	5	t	0
2176	932	4	t	0
2177	933	7	t	0
2178	933	8	t	0.25
2179	934	2	t	0
2180	934	1	t	0
2181	935	5	t	0
2182	935	8	t	0.25
2183	936	1	t	0
2184	936	7	t	0
2185	937	1	t	0
2186	937	2	t	0
2187	937	5	t	0.5
2188	938	2	t	0
2189	938	4	t	0
2190	938	5	t	0.299999999999999989
2191	939	3	t	0
2192	939	8	t	0
2193	940	6	t	0
2194	940	2	t	0
2195	940	7	t	0.299999999999999989
2196	941	9	t	0
2197	941	2	t	0
2198	941	8	t	0.299999999999999989
2199	942	4	t	0
2200	942	1	t	0
2201	943	4	t	0
2202	943	1	t	0
2203	944	4	t	0
2204	944	6	t	0.25
2205	945	8	t	0
2206	945	6	t	0
2207	946	5	t	0
2208	946	6	t	0
2209	947	8	t	0
2210	947	2	t	0
2211	947	5	t	0.5
2212	948	7	t	0
2213	948	6	t	0
2214	949	5	t	0
2215	949	3	t	0
2216	950	5	t	0
2217	950	2	t	0
2218	951	9	t	0
2219	951	4	t	0.25
2220	952	2	t	0
2221	952	8	t	0
2222	953	5	t	0
2223	953	7	t	0
2224	953	8	t	0.299999999999999989
2225	954	9	t	0
2226	954	6	t	0
2227	955	4	t	0
2228	955	8	t	0
2229	956	5	t	0
2230	956	7	t	0.25
2231	957	4	t	0
2232	957	6	t	0
2233	957	5	t	0.299999999999999989
2234	958	6	t	0
2235	958	1	t	0
2236	958	3	t	0.299999999999999989
2237	959	8	t	0
2238	959	3	t	0
2239	960	8	t	0
2240	960	4	t	0
2241	961	3	t	0
2242	961	5	t	0
2243	962	4	t	0
2244	962	7	t	0
2245	963	9	t	0
2246	963	1	t	0
2247	964	4	t	0
2248	964	8	t	0
2249	964	6	t	0.299999999999999989
2250	965	8	t	0
2251	965	3	t	0
2252	966	7	t	0
2253	966	2	t	0
2254	967	9	t	0
2255	967	6	t	0
2256	968	1	t	0
2257	968	6	t	0
2258	969	2	t	0
2259	969	7	t	0.25
2260	970	3	t	0
2261	970	8	t	0
2262	971	4	t	0
2263	971	8	t	0
2264	972	7	t	0
2265	972	2	t	0.25
2266	973	8	t	0
2267	973	3	t	0.25
2268	974	3	t	0
2269	974	6	t	0
2270	974	5	t	0.299999999999999989
2271	975	3	t	0
2272	975	8	t	0.25
2273	976	7	t	0
2274	976	2	t	0
2275	977	5	t	0
2276	977	8	t	0
2277	978	2	t	0
2278	978	3	t	0
2279	979	6	t	0
2280	979	9	t	0
2281	980	5	t	0
2282	980	9	t	0
2283	981	8	t	0
2284	981	9	t	0
2285	982	7	t	0
2286	982	9	t	0
2287	982	2	t	0.299999999999999989
2288	983	7	t	0
2289	983	6	t	0
2290	984	6	t	0
2291	984	1	t	0
2292	985	4	t	0
2293	985	9	t	0
2294	986	6	t	0
2295	986	8	t	0.25
2296	987	7	t	0
2297	987	4	t	0
2298	988	8	t	0
2299	988	1	t	0
2300	989	9	t	0
2301	989	7	t	0
2302	989	8	t	0.299999999999999989
2303	990	2	t	0
2304	990	3	t	0
2305	990	4	t	0.299999999999999989
2306	991	1	t	0
2307	991	5	t	0
2308	992	3	t	0
2309	992	8	t	0
2310	992	5	t	0.299999999999999989
2311	993	3	t	0
2312	993	4	t	0
2313	994	4	t	0
2314	994	1	t	0
2315	995	4	t	0
2316	995	3	t	0
2317	995	1	t	0.299999999999999989
2318	996	3	t	0
2319	996	5	t	0
2320	997	4	t	0
2321	997	5	t	0.25
2322	998	4	t	0
2323	998	1	t	0
2324	999	7	t	0
2325	999	4	t	0.25
2326	1000	7	t	0
2327	1000	6	t	0
2328	1000	9	t	0.299999999999999989
2329	1001	4	t	0
2330	1001	5	t	0
2331	1001	3	t	0.299999999999999989
2332	1002	1	t	0
2333	1002	6	t	0
2334	1003	2	t	0
2335	1003	6	t	0
2336	1003	3	t	0.299999999999999989
2337	1004	6	t	0
2338	1004	3	t	0
2339	1005	9	t	0
2340	1005	2	t	0
2341	1006	5	t	0
2342	1006	3	t	0
2343	1007	3	t	0
2344	1007	5	t	0.25
2345	1008	2	t	0
2346	1008	7	t	0
2347	1008	4	t	0.299999999999999989
2348	1009	8	t	0
2349	1009	7	t	0.25
2350	1010	7	t	0
2351	1010	8	t	0
2352	1011	3	t	0
2353	1011	2	t	0.25
2354	1012	9	t	0
2355	1012	7	t	0
2356	1012	4	t	0.299999999999999989
2357	1013	2	t	0
2358	1013	5	t	0
2359	1014	7	t	0
2360	1014	5	t	0
2361	1015	8	t	0
2362	1015	1	t	0
2363	1016	3	t	0
2364	1016	9	t	0.25
2365	1017	5	t	0
2366	1017	7	t	0
2367	1017	3	t	0.299999999999999989
2368	1018	2	t	0
2369	1018	4	t	0.25
2370	1019	7	t	0
2371	1019	4	t	0
2372	1020	4	t	0
2373	1020	1	t	0.25
2374	1021	3	t	0
2375	1021	4	t	0
2376	1022	6	t	0
2377	1022	2	t	0.25
2378	1023	7	t	0
2379	1023	2	t	0
2380	1023	8	t	0.299999999999999989
2381	1024	7	t	0
2382	1024	1	t	0.25
2383	1025	4	t	0
2384	1025	3	t	0
2385	1026	5	t	0
2386	1026	8	t	0
2387	1027	6	t	0
2388	1027	1	t	0.25
2389	1028	3	t	0
2390	1028	2	t	0
2391	1029	8	t	0
2392	1029	1	t	0
2393	1029	5	t	0.299999999999999989
2394	1030	2	t	0
2395	1030	7	t	0
2396	1030	1	t	0.299999999999999989
2397	1031	4	t	0
2398	1031	7	t	0
2399	1031	2	t	0.299999999999999989
2400	1032	1	t	0
2401	1032	9	t	0
2402	1033	9	t	0
2403	1033	4	t	0
2404	1033	5	t	0.299999999999999989
2405	1034	3	t	0
2406	1034	5	t	0.25
2407	1035	4	t	0
2408	1035	5	t	0
2409	1036	7	t	0
2410	1036	2	t	0
2411	1036	6	t	0.299999999999999989
2412	1037	1	t	0
2413	1037	7	t	0
2414	1037	5	t	0.5
2415	1038	9	t	0
2416	1038	2	t	0
2417	1039	1	t	0
2418	1039	2	t	0
2419	1040	9	t	0
2420	1040	8	t	0
2421	1041	4	t	0
2422	1041	7	t	0.25
2423	1041	9	t	0.299999999999999989
2424	1042	4	t	0
2425	1042	3	t	0
2426	1043	8	t	0
2427	1043	2	t	0
2428	1044	1	t	0
2429	1044	9	t	0
2430	1044	7	t	0.299999999999999989
2431	1045	1	t	0
2432	1045	6	t	0
2433	1045	7	t	0.5
2434	1046	4	t	0
2435	1046	5	t	0.25
2436	1047	8	t	0
2437	1047	5	t	0.25
2438	1048	4	t	0
2439	1048	1	t	0
2440	1049	8	t	0
2441	1049	9	t	0
2442	1050	2	t	0
2443	1050	4	t	0
2444	1051	9	t	0
2445	1051	6	t	0
2446	1052	1	t	0
2447	1052	3	t	0.25
2448	1053	8	t	0
2449	1053	7	t	0
2450	1054	9	t	0
2451	1054	1	t	0
2452	1055	4	t	0
2453	1055	9	t	0.25
2454	1055	3	t	0.299999999999999989
2455	1056	3	t	0
2456	1056	5	t	0.25
2457	1057	4	t	0
2458	1057	5	t	0.25
2459	1058	6	t	0
2460	1058	8	t	0
2461	1058	4	t	0.299999999999999989
2462	1059	9	t	0
2463	1059	5	t	0
2464	1060	6	t	0
2465	1060	7	t	0
2466	1061	9	t	0
2467	1061	6	t	0.25
2468	1061	5	t	0.299999999999999989
2469	1062	6	t	0
2470	1062	9	t	0
2471	1063	8	t	0
2472	1063	6	t	0.25
2473	1063	1	t	0.299999999999999989
2474	1064	3	t	0
2475	1064	4	t	0
2476	1065	6	t	0
2477	1065	8	t	0
2478	1066	1	t	0
2479	1066	4	t	0
2480	1067	2	t	0
2481	1067	1	t	0
2482	1068	6	t	0
2483	1068	3	t	0
2484	1069	7	t	0
2485	1069	4	t	0
2486	1070	7	t	0
2487	1070	1	t	0
2488	1070	2	t	0.299999999999999989
2489	1071	6	t	0
2490	1071	7	t	0.25
2491	1071	4	t	0.299999999999999989
2492	1072	4	t	0
2493	1072	3	t	0
2494	1072	5	t	0.299999999999999989
2495	1073	2	t	0
2496	1073	4	t	0
2497	1074	4	t	0
2498	1074	3	t	0.25
2499	1074	8	t	0.299999999999999989
2500	1075	2	t	0
2501	1075	7	t	0
2502	1076	4	t	0
2503	1076	9	t	0
2504	1077	8	t	0
2505	1077	1	t	0
2506	1078	8	t	0
2507	1078	6	t	0
2508	1079	4	t	0
2509	1079	7	t	0
2510	1080	8	t	0
2511	1080	9	t	0
2512	1080	3	t	0.299999999999999989
2513	1081	3	t	0
2514	1081	6	t	0
2515	1082	6	t	0
2516	1082	9	t	0
2517	1083	5	t	0
2518	1083	9	t	0.25
2519	1083	8	t	0.299999999999999989
2520	1084	4	t	0
2521	1084	3	t	0
2522	1085	7	t	0
2523	1085	6	t	0
2524	1086	6	t	0
2525	1086	1	t	0
2526	1087	7	t	0
2527	1087	1	t	0
2528	1087	4	t	0.299999999999999989
2529	1088	6	t	0
2530	1088	9	t	0
2531	1089	1	t	0
2532	1089	2	t	0
2533	1089	9	t	0.299999999999999989
2534	1090	4	t	0
2535	1090	7	t	0
2536	1091	2	t	0
2537	1091	5	t	0
2538	1092	2	t	0
2539	1092	7	t	0
2540	1093	9	t	0
2541	1093	3	t	0
2542	1094	9	t	0
2543	1094	2	t	0
2544	1095	4	t	0
2545	1095	6	t	0.25
2546	1096	8	t	0
2547	1096	6	t	0
2548	1097	8	t	0
2549	1097	2	t	0
2550	1098	4	t	0
2551	1098	8	t	0
2552	1099	6	t	0
2553	1099	1	t	0
2554	1100	3	t	0
2555	1100	5	t	0.25
2556	1100	2	t	0.299999999999999989
2557	1101	7	t	0
2558	1101	3	t	0
2559	1101	1	t	0.299999999999999989
2560	1102	6	t	0
2561	1102	2	t	0
2562	1103	6	t	0
2563	1103	4	t	0
2564	1104	5	t	0
2565	1104	6	t	0
2566	1105	5	t	0
2567	1105	6	t	0.25
2568	1106	9	t	0
2569	1106	1	t	0.25
2570	1107	4	t	0
2571	1107	1	t	0
2572	1108	5	t	0
2573	1108	6	t	0
2574	1109	9	t	0
2575	1109	3	t	0
2576	1110	8	t	0
2577	1110	4	t	0
2578	1110	2	t	0.299999999999999989
2579	1111	2	t	0
2580	1111	4	t	0
2581	1112	6	t	0
2582	1112	1	t	0.25
2583	1113	8	t	0
2584	1113	1	t	0.25
2585	1114	6	t	0
2586	1114	1	t	0
2587	1115	4	t	0
2588	1115	8	t	0
2589	1115	7	t	0.299999999999999989
2590	1116	4	t	0
2591	1116	2	t	0
2592	1117	1	t	0
2593	1117	7	t	0
2594	1118	5	t	0
2595	1118	7	t	0
2596	1119	9	t	0
2597	1119	4	t	0
2598	1120	6	t	0
2599	1120	8	t	0
2600	1121	9	t	0
2601	1121	5	t	0.25
2602	1121	3	t	0.299999999999999989
2603	1122	4	t	0
2604	1122	6	t	0
2605	1122	8	t	0.299999999999999989
2606	1123	8	t	0
2607	1123	6	t	0
2608	1124	1	t	0
2609	1124	8	t	0
2610	1124	2	t	0.299999999999999989
2611	1125	9	t	0
2612	1125	3	t	0
2613	1126	5	t	0
2614	1126	6	t	0
2615	1127	9	t	0
2616	1127	7	t	0
2617	1127	1	t	0.299999999999999989
2618	1128	5	t	0
2619	1128	8	t	0
2620	1129	2	t	0
2621	1129	9	t	0
2622	1130	4	t	0
2623	1130	9	t	0
2624	1131	4	t	0
2625	1131	5	t	0
2626	1132	9	t	0
2627	1132	8	t	0
2628	1132	6	t	0.299999999999999989
2629	1133	8	t	0
2630	1133	6	t	0
2631	1134	4	t	0
2632	1134	7	t	0
2633	1135	2	t	0
2634	1135	1	t	0
2635	1135	3	t	0.299999999999999989
2636	1136	4	t	0
2637	1136	3	t	0
2638	1137	5	t	0
2639	1137	6	t	0
2640	1138	1	t	0
2641	1138	7	t	0
2642	1139	8	t	0
2643	1139	7	t	0
2644	1140	5	t	0
2645	1140	9	t	0
2646	1141	9	t	0
2647	1141	3	t	0
2648	1141	6	t	0.299999999999999989
2649	1142	3	t	0
2650	1142	5	t	0
2651	1143	5	t	0
2652	1143	2	t	0
2653	1143	9	t	0.299999999999999989
2654	1144	7	t	0
2655	1144	6	t	0
2656	1144	9	t	0.299999999999999989
2657	1145	1	t	0
2658	1145	8	t	0
2659	1145	3	t	0.299999999999999989
2660	1146	3	t	0
2661	1146	2	t	0
2662	1147	6	t	0
2663	1147	7	t	0.25
2664	1147	9	t	0.299999999999999989
2665	1148	3	t	0
2666	1148	5	t	0
2667	1149	1	t	0
2668	1149	5	t	0.25
2669	1150	6	t	0
2670	1150	7	t	0
2671	1151	7	t	0
2672	1151	5	t	0.25
2673	1151	9	t	0.299999999999999989
2674	1152	3	t	0
2675	1152	6	t	0
2676	1153	3	t	0
2677	1153	6	t	0
2678	1154	6	t	0
2679	1154	5	t	0
2680	1155	7	t	0
2681	1155	3	t	0
2682	1156	3	t	0
2683	1156	8	t	0
2684	1157	9	t	0
2685	1157	3	t	0
2686	1157	6	t	0.299999999999999989
2687	1158	9	t	0
2688	1158	5	t	0.25
2689	1158	8	t	0.299999999999999989
2690	1159	6	t	0
2691	1159	9	t	0
2692	1160	5	t	0
2693	1160	2	t	0.25
2694	1161	9	t	0
2695	1161	2	t	0.25
2696	1162	5	t	0
2697	1162	3	t	0
2698	1162	8	t	0.299999999999999989
2699	1163	7	t	0
2700	1163	8	t	0.25
2701	1163	2	t	0.299999999999999989
2702	1164	7	t	0
2703	1164	1	t	0
2704	1165	9	t	0
2705	1165	5	t	0
2706	1166	4	t	0
2707	1166	5	t	0.25
2708	1167	8	t	0
2709	1167	1	t	0
2710	1167	3	t	0.299999999999999989
2711	1168	6	t	0
2712	1168	4	t	0
2713	1169	6	t	0
2714	1169	8	t	0
2715	1170	3	t	0
2716	1170	5	t	0.25
2717	1171	3	t	0
2718	1171	7	t	0
2719	1171	9	t	0.299999999999999989
2720	1172	4	t	0
2721	1172	8	t	0
2722	1173	8	t	0
2723	1173	1	t	0
2724	1174	7	t	0
2725	1174	2	t	0
2726	1174	6	t	0.299999999999999989
2727	1175	8	t	0
2728	1175	9	t	0
2729	1175	2	t	0.299999999999999989
2730	1176	9	t	0
2731	1176	1	t	0
2732	1176	2	t	0.299999999999999989
2733	1177	4	t	0
2734	1177	1	t	0.25
2735	1178	9	t	0
2736	1178	1	t	0
2737	1179	5	t	0
2738	1179	9	t	0
2739	1180	2	t	0
2740	1180	4	t	0
2741	1181	7	t	0
2742	1181	1	t	0
2743	1182	1	t	0
2744	1182	2	t	0
2745	1183	5	t	0
2746	1183	7	t	0.25
2747	1184	2	t	0
2748	1184	1	t	0
2749	1184	3	t	0.299999999999999989
2750	1185	1	t	0
2751	1185	2	t	0
2752	1186	6	t	0
2753	1186	2	t	0
2754	1187	4	t	0
2755	1187	1	t	0
2756	1187	6	t	0.299999999999999989
2757	1188	8	t	0
2758	1188	4	t	0
2759	1188	2	t	0.5
2760	1189	9	t	0
2761	1189	6	t	0
2762	1190	2	t	0
2763	1190	9	t	0
2764	1190	6	t	0.299999999999999989
2765	1191	3	t	0
2766	1191	8	t	0
2767	1192	1	t	0
2768	1192	4	t	0
2769	1193	4	t	0
2770	1193	7	t	0
2771	1193	9	t	0.299999999999999989
2772	1194	3	t	0
2773	1194	9	t	0
2774	1194	6	t	0.299999999999999989
2775	1195	5	t	0
2776	1195	6	t	0
2777	1196	8	t	0
2778	1196	6	t	0
2779	1196	2	t	0.299999999999999989
2780	1197	4	t	0
2781	1197	6	t	0
2782	1198	8	t	0
2783	1198	6	t	0
2784	1199	1	t	0
2785	1199	7	t	0
2786	1200	9	t	0
2787	1200	3	t	0
2788	1201	2	t	0
2789	1201	6	t	0
2790	1202	9	t	0
2791	1202	2	t	0.25
2792	1203	7	t	0
2793	1203	9	t	0
2794	1204	4	t	0
2795	1204	6	t	0
2796	1205	7	t	0
2797	1205	9	t	0
2798	1206	7	t	0
2799	1206	1	t	0
2800	1206	4	t	0.299999999999999989
2801	1207	6	t	0
2802	1207	8	t	0
2803	1208	2	t	0
2804	1208	9	t	0
2805	1208	5	t	0.299999999999999989
2806	1209	5	t	0
2807	1209	9	t	0
2808	1209	3	t	0.299999999999999989
2809	1210	6	t	0
2810	1210	3	t	0
2811	1211	2	t	0
2812	1211	7	t	0
2813	1212	1	t	0
2814	1212	3	t	0
2815	1212	4	t	0.299999999999999989
2816	1213	1	t	0
2817	1213	9	t	0.25
2818	1214	1	t	0
2819	1214	8	t	0
2820	1215	1	t	0
2821	1215	9	t	0
2822	1215	6	t	0.299999999999999989
2823	1216	4	t	0
2824	1216	7	t	0
2825	1216	9	t	0.299999999999999989
2826	1217	8	t	0
2827	1217	1	t	0.25
2828	1218	5	t	0
2829	1218	4	t	0
2830	1219	9	t	0
2831	1219	5	t	0
2832	1220	4	t	0
2833	1220	5	t	0
2834	1220	3	t	0.299999999999999989
2835	1221	5	t	0
2836	1221	7	t	0.25
2837	1222	1	t	0
2838	1222	8	t	0
2839	1223	2	t	0
2840	1223	6	t	0
2841	1223	7	t	0.299999999999999989
2842	1224	7	t	0
2843	1224	3	t	0
2844	1225	4	t	0
2845	1225	6	t	0.25
2846	1225	8	t	0.299999999999999989
2847	1226	1	t	0
2848	1226	3	t	0
2849	1227	3	t	0
2850	1227	7	t	0
2851	1227	4	t	0.299999999999999989
2852	1228	8	t	0
2853	1228	5	t	0.25
2854	1229	1	t	0
2855	1229	2	t	0.25
2856	1230	1	t	0
2857	1230	6	t	0.25
2858	1231	7	t	0
2859	1231	2	t	0
2860	1232	4	t	0
2861	1232	8	t	0
2862	1232	3	t	0.299999999999999989
2863	1233	3	t	0
2864	1233	6	t	0
2865	1233	5	t	0.299999999999999989
2866	1234	3	t	0
2867	1234	2	t	0
2868	1235	2	t	0
2869	1235	9	t	0
2870	1236	9	t	0
2871	1236	1	t	0
2872	1236	5	t	0.299999999999999989
2873	1237	8	t	0
2874	1237	2	t	0
2875	1238	8	t	0
2876	1238	1	t	0
2877	1239	9	t	0
2878	1239	3	t	0
2879	1239	5	t	0.5
2880	1240	9	t	0
2881	1240	1	t	0
2882	1240	2	t	0.299999999999999989
2883	1241	8	t	0
2884	1241	2	t	0
2885	1241	9	t	0.299999999999999989
2886	1242	2	t	0
2887	1242	5	t	0.25
2888	1243	1	t	0
2889	1243	2	t	0
2890	1244	9	t	0
2891	1244	3	t	0
2892	1244	1	t	0.5
2893	1245	5	t	0
2894	1245	2	t	0.25
2895	1246	6	t	0
2896	1246	1	t	0
2897	1247	4	t	0
2898	1247	8	t	0
2899	1247	7	t	0.299999999999999989
2900	1248	8	t	0
2901	1248	3	t	0
2902	1248	5	t	0.299999999999999989
2903	1249	9	t	0
2904	1249	2	t	0
2905	1249	1	t	0.299999999999999989
2906	1250	3	t	0
2907	1250	7	t	0
2908	1251	6	t	0
2909	1251	8	t	0
2910	1251	2	t	0.299999999999999989
2911	1252	6	t	0
2912	1252	5	t	0.25
2913	1252	7	t	0.299999999999999989
2914	1253	8	t	0
2915	1253	1	t	0
2916	1254	2	t	0
2917	1254	7	t	0
2918	1255	7	t	0
2919	1255	3	t	0
2920	1256	5	t	0
2921	1256	2	t	0
2922	1257	5	t	0
2923	1257	2	t	0
2924	1257	6	t	0.299999999999999989
2925	1258	1	t	0
2926	1258	7	t	0
2927	1259	3	t	0
2928	1259	9	t	0
2929	1259	2	t	0.299999999999999989
2930	1260	9	t	0
2931	1260	1	t	0
2932	1260	2	t	0.299999999999999989
2933	1261	6	t	0
2934	1261	1	t	0
2935	1262	6	t	0
2936	1262	3	t	0
2937	1263	6	t	0
2938	1263	5	t	0.25
2939	1264	2	t	0
2940	1264	3	t	0
2941	1265	6	t	0
2942	1265	9	t	0
2943	1266	3	t	0
2944	1266	6	t	0
2945	1267	1	t	0
2946	1267	4	t	0
2947	1267	9	t	0.299999999999999989
2948	1268	3	t	0
2949	1268	9	t	0
2950	1269	3	t	0
2951	1269	9	t	0
2952	1269	6	t	0.299999999999999989
2953	1270	4	t	0
2954	1270	7	t	0
2955	1270	1	t	0.299999999999999989
2956	1271	9	t	0
2957	1271	4	t	0
2958	1271	7	t	0.299999999999999989
2959	1272	6	t	0
2960	1272	2	t	0.25
2961	1273	2	t	0
2962	1273	5	t	0
2963	1274	3	t	0
2964	1274	2	t	0
2965	1275	6	t	0
2966	1275	1	t	0.25
2967	1276	8	t	0
2968	1276	2	t	0
2969	1277	8	t	0
2970	1277	4	t	0
2971	1277	5	t	0.299999999999999989
2972	1278	1	t	0
2973	1278	5	t	0
2974	1279	5	t	0
2975	1279	6	t	0
2976	1279	4	t	0.299999999999999989
2977	1280	7	t	0
2978	1280	6	t	0
2979	1280	8	t	0.5
2980	1281	2	t	0
2981	1281	8	t	0
2982	1282	6	t	0
2983	1282	5	t	0
2984	1282	3	t	0.299999999999999989
2985	1283	6	t	0
2986	1283	8	t	0
2987	1283	1	t	0.299999999999999989
2988	1284	4	t	0
2989	1284	2	t	0
2990	1285	1	t	0
2991	1285	4	t	0
2992	1285	6	t	0.299999999999999989
2993	1286	5	t	0
2994	1286	6	t	0.25
2995	1286	9	t	0.299999999999999989
2996	1287	3	t	0
2997	1287	1	t	0
2998	1288	1	t	0
2999	1288	4	t	0
3000	1289	2	t	0
3001	1289	6	t	0
3002	1290	1	t	0
3003	1290	9	t	0
3004	1291	3	t	0
3005	1291	8	t	0
3006	1292	9	t	0
3007	1292	3	t	0
3008	1293	2	t	0
3009	1293	8	t	0
3010	1293	4	t	0.299999999999999989
3011	1294	3	t	0
3012	1294	1	t	0
3013	1295	5	t	0
3014	1295	9	t	0
3015	1296	4	t	0
3016	1296	7	t	0
3017	1296	2	t	0.299999999999999989
3018	1297	3	t	0
3019	1297	5	t	0
3020	1298	5	t	0
3021	1298	4	t	0
3022	1298	7	t	0.299999999999999989
3023	1299	3	t	0
3024	1299	8	t	0
3025	1299	1	t	0.299999999999999989
3026	1300	2	t	0
3027	1300	6	t	0
3028	1301	5	t	0
3029	1301	1	t	0
3030	1301	9	t	0.299999999999999989
3031	1302	7	t	0
3032	1302	9	t	0
3033	1303	5	t	0
3034	1303	6	t	0
3035	1304	1	t	0
3036	1304	4	t	0
3037	1305	8	t	0
3038	1305	6	t	0
3039	1306	6	t	0
3040	1306	2	t	0
3041	1307	8	t	0
3042	1307	1	t	0.25
3043	1308	9	t	0
3044	1308	3	t	0
3045	1308	7	t	0.299999999999999989
3046	1309	5	t	0
3047	1309	1	t	0.25
3048	1310	9	t	0
3049	1310	4	t	0
3050	1310	8	t	0.299999999999999989
3051	1311	8	t	0
3052	1311	2	t	0.25
3053	1311	6	t	0.299999999999999989
3054	1312	2	t	0
3055	1312	4	t	0.25
3056	1313	4	t	0
3057	1313	5	t	0
3058	1314	8	t	0
3059	1314	2	t	0
3060	1315	5	t	0
3061	1315	6	t	0.25
3062	1316	9	t	0
3063	1316	8	t	0
3064	1316	7	t	0.299999999999999989
3065	1317	8	t	0
3066	1317	3	t	0
3067	1317	1	t	0.299999999999999989
3068	1318	7	t	0
3069	1318	3	t	0.25
3070	1319	9	t	0
3071	1319	2	t	0.25
3072	1320	5	t	0
3073	1320	4	t	0
3074	1321	4	t	0
3075	1321	8	t	0.25
3076	1322	1	t	0
3077	1322	9	t	0
3078	1322	4	t	0.299999999999999989
3079	1323	1	t	0
3080	1323	4	t	0
3081	1323	2	t	0.299999999999999989
3082	1324	1	t	0
3083	1324	2	t	0
3084	1325	8	t	0
3085	1325	1	t	0
3086	1326	9	t	0
3087	1326	3	t	0
3088	1327	3	t	0
3089	1327	2	t	0
3090	1328	3	t	0
3091	1328	7	t	0
3092	1329	7	t	0
3093	1329	3	t	0
3094	1330	4	t	0
3095	1330	2	t	0.25
3096	1331	1	t	0
3097	1331	3	t	0
3098	1332	3	t	0
3099	1332	2	t	0
3100	1332	6	t	0.299999999999999989
3101	1333	4	t	0
3102	1333	6	t	0
3103	1334	7	t	0
3104	1334	8	t	0
3105	1335	6	t	0
3106	1335	3	t	0.25
3107	1336	5	t	0
3108	1336	3	t	0
3109	1337	7	t	0
3110	1337	6	t	0.25
3111	1338	3	t	0
3112	1338	8	t	0
3113	1338	4	t	0.299999999999999989
3114	1339	3	t	0
3115	1339	1	t	0
3116	1340	6	t	0
3117	1340	1	t	0
3118	1341	2	t	0
3119	1341	9	t	0.25
3120	1341	3	t	0.299999999999999989
3121	1342	6	t	0
3122	1342	7	t	0
3123	1343	1	t	0
3124	1343	2	t	0
3125	1344	4	t	0
3126	1344	7	t	0
3127	1345	8	t	0
3128	1345	7	t	0
3129	1345	5	t	0.5
3130	1346	6	t	0
3131	1346	2	t	0
3132	1347	4	t	0
3133	1347	6	t	0
3134	1348	2	t	0
3135	1348	3	t	0
3136	1349	6	t	0
3137	1349	1	t	0
3138	1349	2	t	0.299999999999999989
3139	1350	5	t	0
3140	1350	9	t	0.25
3141	1351	7	t	0
3142	1351	2	t	0
3143	1352	8	t	0
3144	1352	6	t	0
3145	1352	1	t	0.299999999999999989
3146	1353	8	t	0
3147	1353	5	t	0
3148	1353	9	t	0.299999999999999989
3149	1354	9	t	0
3150	1354	7	t	0
3151	1355	4	t	0
3152	1355	6	t	0
3153	1356	5	t	0
3154	1356	3	t	0
3155	1356	6	t	0.5
3156	1357	3	t	0
3157	1357	7	t	0
3158	1357	5	t	0.299999999999999989
3159	1358	6	t	0
3160	1358	5	t	0
3161	1358	7	t	0.299999999999999989
3162	1359	6	t	0
3163	1359	5	t	0
3164	1360	4	t	0
3165	1360	9	t	0
3166	1360	7	t	0.299999999999999989
3167	1361	7	t	0
3168	1361	4	t	0
3169	1361	3	t	0.299999999999999989
3170	1362	5	t	0
3171	1362	4	t	0
3172	1363	4	t	0
3173	1363	7	t	0
3174	1364	3	t	0
3175	1364	4	t	0
3176	1365	9	t	0
3177	1365	1	t	0
3178	1366	2	t	0
3179	1366	3	t	0
3180	1366	5	t	0.299999999999999989
3181	1367	9	t	0
3182	1367	6	t	0
3183	1368	4	t	0
3184	1368	3	t	0
3185	1368	6	t	0.299999999999999989
3186	1369	2	t	0
3187	1369	4	t	0
3188	1370	6	t	0
3189	1370	3	t	0
3190	1370	1	t	0.5
3191	1371	6	t	0
3192	1371	4	t	0
3193	1371	9	t	0.299999999999999989
3194	1372	2	t	0
3195	1372	3	t	0
3196	1373	4	t	0
3197	1373	6	t	0
3198	1374	1	t	0
3199	1374	6	t	0
3200	1374	3	t	0.299999999999999989
3201	1375	3	t	0
3202	1375	5	t	0
3203	1376	7	t	0
3204	1376	8	t	0
3205	1377	8	t	0
3206	1377	1	t	0.25
3207	1378	4	t	0
3208	1378	5	t	0
3209	1379	1	t	0
3210	1379	4	t	0
3211	1380	3	t	0
3212	1380	4	t	0
3213	1381	5	t	0
3214	1381	8	t	0
3215	1381	2	t	0.299999999999999989
3216	1382	4	t	0
3217	1382	9	t	0
3218	1383	9	t	0
3219	1383	3	t	0
3220	1383	5	t	0.299999999999999989
3221	1384	6	t	0
3222	1384	8	t	0
3223	1384	2	t	0.299999999999999989
3224	1385	9	t	0
3225	1385	5	t	0
3226	1386	4	t	0
3227	1386	9	t	0
3228	1387	9	t	0
3229	1387	4	t	0
3230	1388	7	t	0
3231	1388	4	t	0
3232	1389	5	t	0
3233	1389	4	t	0
3234	1390	8	t	0
3235	1390	5	t	0
3236	1391	3	t	0
3237	1391	8	t	0
3238	1392	3	t	0
3239	1392	5	t	0
3240	1393	2	t	0
3241	1393	8	t	0
3242	1393	1	t	0.299999999999999989
3243	1394	6	t	0
3244	1394	1	t	0.25
3245	1395	7	t	0
3246	1395	3	t	0
3247	1396	8	t	0
3248	1396	5	t	0
3249	1397	8	t	0
3250	1397	6	t	0
3251	1398	6	t	0
3252	1398	1	t	0
3253	1398	3	t	0.299999999999999989
3254	1399	9	t	0
3255	1399	2	t	0
3256	1400	8	t	0
3257	1400	6	t	0
3258	1401	2	t	0
3259	1401	6	t	0
3260	1402	4	t	0
3261	1402	6	t	0.25
3262	1402	9	t	0.299999999999999989
3263	1403	9	t	0
3264	1403	7	t	0.25
3265	1404	4	t	0
3266	1404	6	t	0
3267	1404	9	t	0.299999999999999989
3268	1405	6	t	0
3269	1405	2	t	0
3270	1406	9	t	0
3271	1406	6	t	0
3272	1407	5	t	0
3273	1407	7	t	0
3274	1408	8	t	0
3275	1408	9	t	0
3276	1409	2	t	0
3277	1409	7	t	0
3278	1409	1	t	0.299999999999999989
3279	1410	7	t	0
3280	1410	9	t	0
3281	1411	4	t	0
3282	1411	8	t	0
3283	1412	3	t	0
3284	1412	1	t	0
3285	1413	1	t	0
3286	1413	2	t	0
3287	1414	2	t	0
3288	1414	9	t	0
3289	1415	1	t	0
3290	1415	6	t	0
3291	1416	9	t	0
3292	1416	6	t	0
3293	1417	5	t	0
3294	1417	8	t	0
3295	1418	4	t	0
3296	1418	3	t	0
3297	1419	6	t	0
3298	1419	4	t	0
3299	1420	2	t	0
3300	1420	9	t	0
3301	1421	5	t	0
3302	1421	2	t	0
3303	1421	8	t	0.299999999999999989
3304	1422	1	t	0
3305	1422	8	t	0
3306	1423	8	t	0
3307	1423	3	t	0.25
3308	1424	9	t	0
3309	1424	6	t	0
3310	1425	7	t	0
3311	1425	5	t	0
3312	1426	2	t	0
3313	1426	8	t	0.25
3314	1426	3	t	0.299999999999999989
3315	1427	9	t	0
3316	1427	4	t	0
3317	1428	2	t	0
3318	1428	9	t	0
3319	1428	1	t	0.299999999999999989
3320	1429	4	t	0
3321	1429	1	t	0
3322	1429	5	t	0.299999999999999989
3323	1430	9	t	0
3324	1430	3	t	0
3325	1431	8	t	0
3326	1431	1	t	0
3327	1431	7	t	0.299999999999999989
3328	1432	2	t	0
3329	1432	1	t	0
3330	1432	6	t	0.299999999999999989
3331	1433	9	t	0
3332	1433	5	t	0.25
3333	1434	4	t	0
3334	1434	2	t	0
3335	1435	3	t	0
3336	1435	6	t	0
3337	1436	6	t	0
3338	1436	2	t	0
3339	1437	4	t	0
3340	1437	5	t	0
3341	1438	1	t	0
3342	1438	5	t	0
3343	1439	4	t	0
3344	1439	9	t	0.25
3345	1440	1	t	0
3346	1440	3	t	0.25
3347	1441	1	t	0
3348	1441	3	t	0
3349	1442	3	t	0
3350	1442	7	t	0
3351	1442	1	t	0.299999999999999989
3352	1443	5	t	0
3353	1443	6	t	0.25
3354	1443	1	t	0.299999999999999989
3355	1444	3	t	0
3356	1444	7	t	0.25
3357	1445	8	t	0
3358	1445	6	t	0
3359	1445	9	t	0.299999999999999989
3360	1446	6	t	0
3361	1446	7	t	0
3362	1446	9	t	0.299999999999999989
3363	1447	1	t	0
3364	1447	9	t	0
3365	1448	4	t	0
3366	1448	3	t	0
3367	1448	6	t	0.299999999999999989
3368	1449	6	t	0
3369	1449	8	t	0
3370	1449	9	t	0.299999999999999989
3371	1450	8	t	0
3372	1450	9	t	0
3373	1450	2	t	0.299999999999999989
3374	1451	7	t	0
3375	1451	2	t	0
3376	1452	3	t	0
3377	1452	6	t	0
3378	1453	5	t	0
3379	1453	3	t	0.25
3380	1453	6	t	0.299999999999999989
3381	1454	1	t	0
3382	1454	3	t	0
3383	1455	2	t	0
3384	1455	6	t	0
3385	1456	6	t	0
3386	1456	8	t	0
3387	1457	2	t	0
3388	1457	6	t	0
3389	1458	8	t	0
3390	1458	5	t	0
3391	1459	7	t	0
3392	1459	1	t	0
3393	1460	5	t	0
3394	1460	3	t	0
3395	1461	9	t	0
3396	1461	1	t	0.25
3397	1462	4	t	0
3398	1462	1	t	0.25
3399	1463	1	t	0
3400	1463	3	t	0
3401	1464	4	t	0
3402	1464	2	t	0
3403	1465	2	t	0
3404	1465	6	t	0
3405	1466	8	t	0
3406	1466	7	t	0
3407	1467	9	t	0
3408	1467	3	t	0
3409	1467	2	t	0.5
3410	1468	3	t	0
3411	1468	4	t	0
3412	1469	1	t	0
3413	1469	3	t	0
3414	1470	6	t	0
3415	1470	4	t	0.25
3416	1470	8	t	0.299999999999999989
3417	1471	8	t	0
3418	1471	6	t	0
3419	1472	5	t	0
3420	1472	7	t	0
3421	1472	9	t	0.299999999999999989
3422	1473	9	t	0
3423	1473	3	t	0
3424	1473	8	t	0.299999999999999989
3425	1474	5	t	0
3426	1474	1	t	0
3427	1474	9	t	0.5
3428	1475	7	t	0
3429	1475	5	t	0
3430	1476	6	t	0
3431	1476	9	t	0
3432	1476	7	t	0.299999999999999989
3433	1477	9	t	0
3434	1477	8	t	0
3435	1477	6	t	0.299999999999999989
3436	1478	5	t	0
3437	1478	6	t	0
3438	1479	7	t	0
3439	1479	2	t	0
3440	1480	7	t	0
3441	1480	8	t	0
3442	1481	3	t	0
3443	1481	9	t	0
3444	1482	1	t	0
3445	1482	8	t	0.25
3446	1482	4	t	0.299999999999999989
3447	1483	7	t	0
3448	1483	5	t	0
3449	1484	7	t	0
3450	1484	3	t	0
3451	1485	2	t	0
3452	1485	9	t	0
3453	1486	1	t	0
3454	1486	3	t	0
3455	1486	2	t	0.299999999999999989
3456	1487	5	t	0
3457	1487	8	t	0
3458	1487	1	t	0.299999999999999989
3459	1488	4	t	0
3460	1488	6	t	0
3461	1488	9	t	0.299999999999999989
3462	1489	6	t	0
3463	1489	3	t	0.25
3464	1490	8	t	0
3465	1490	5	t	0
3466	1490	9	t	0.299999999999999989
3467	1491	1	t	0
3468	1491	2	t	0
3469	1492	2	t	0
3470	1492	7	t	0
3471	1492	8	t	0.299999999999999989
3472	1493	7	t	0
3473	1493	8	t	0
3474	1494	6	t	0
3475	1494	4	t	0
3476	1494	9	t	0.299999999999999989
3477	1495	6	t	0
3478	1495	4	t	0
3479	1496	9	t	0
3480	1496	6	t	0.25
3481	1497	2	t	0
3482	1497	3	t	0.25
3483	1497	4	t	0.299999999999999989
3484	1498	2	t	0
3485	1498	3	t	0
3486	1499	6	t	0
3487	1499	1	t	0
3488	1500	3	t	0
3489	1500	2	t	0
3490	1500	1	t	0.299999999999999989
3491	1501	9	t	0
3492	1501	3	t	0
3493	1501	8	t	0.299999999999999989
3494	1502	7	t	0
3495	1502	3	t	0
3496	1502	1	t	0.299999999999999989
3497	1503	5	t	0
3498	1503	1	t	0
3499	1504	1	t	0
3500	1504	4	t	0
3501	1504	9	t	0.299999999999999989
3502	1505	7	t	0
3503	1505	4	t	0
3504	1506	6	t	0
3505	1506	4	t	0
3506	1507	4	t	0
3507	1507	7	t	0
3508	1507	3	t	0.299999999999999989
3509	1508	5	t	0
3510	1508	9	t	0
3511	1508	3	t	0.299999999999999989
3512	1509	5	t	0
3513	1509	7	t	0
3514	1510	6	t	0
3515	1510	8	t	0.25
3516	1510	4	t	0.299999999999999989
3517	1511	2	t	0
3518	1511	7	t	0
3519	1512	6	t	0
3520	1512	7	t	0
3521	1513	9	t	0
3522	1513	5	t	0
3523	1513	1	t	0.299999999999999989
3524	1514	1	t	0
3525	1514	7	t	0
3526	1515	3	t	0
3527	1515	7	t	0
3528	1515	2	t	0.299999999999999989
3529	1516	6	t	0
3530	1516	4	t	0
3531	1517	9	t	0
3532	1517	2	t	0
3533	1518	3	t	0
3534	1518	5	t	0
3535	1518	4	t	0.299999999999999989
3536	1519	5	t	0
3537	1519	9	t	0
3538	1520	5	t	0
3539	1520	7	t	0
3540	1521	2	t	0
3541	1521	6	t	0
3542	1521	7	t	0.299999999999999989
3543	1522	1	t	0
3544	1522	9	t	0
3545	1523	4	t	0
3546	1523	7	t	0
3547	1523	2	t	0.299999999999999989
3548	1524	3	t	0
3549	1524	9	t	0
3550	1525	5	t	0
3551	1525	4	t	0
3552	1526	9	t	0
3553	1526	1	t	0
3554	1527	8	t	0
3555	1527	9	t	0
3556	1528	6	t	0
3557	1528	5	t	0
3558	1529	3	t	0
3559	1529	1	t	0
3560	1530	5	t	0
3561	1530	1	t	0.25
3562	1531	5	t	0
3563	1531	9	t	0.25
3564	1532	6	t	0
3565	1532	1	t	0
3566	1533	6	t	0
3567	1533	9	t	0
3568	1534	6	t	0
3569	1534	1	t	0
3570	1535	4	t	0
3571	1535	7	t	0
3572	1536	4	t	0
3573	1536	5	t	0
3574	1537	7	t	0
3575	1537	1	t	0
3576	1538	9	t	0
3577	1538	8	t	0
3578	1539	9	t	0
3579	1539	4	t	0
3580	1540	6	t	0
3581	1540	7	t	0
3582	1541	9	t	0
3583	1541	6	t	0
3584	1541	8	t	0.299999999999999989
3585	1542	9	t	0
3586	1542	6	t	0
3587	1542	1	t	0.299999999999999989
3588	1543	5	t	0
3589	1543	7	t	0
3590	1543	8	t	0.299999999999999989
3591	1544	5	t	0
3592	1544	7	t	0.25
3593	1544	6	t	0.299999999999999989
3594	1545	5	t	0
3595	1545	3	t	0
3596	1546	7	t	0
3597	1546	1	t	0
3598	1546	8	t	0.299999999999999989
3599	1547	4	t	0
3600	1547	1	t	0
3601	1548	4	t	0
3602	1548	3	t	0
3603	1549	5	t	0
3604	1549	6	t	0
3605	1550	7	t	0
3606	1550	2	t	0
3607	1551	2	t	0
3608	1551	4	t	0
3609	1551	6	t	0.5
3610	1552	1	t	0
3611	1552	3	t	0
3612	1553	1	t	0
3613	1553	6	t	0
3614	1554	4	t	0
3615	1554	5	t	0
3616	1555	5	t	0
3617	1555	1	t	0
3618	1556	6	t	0
3619	1556	9	t	0
3620	1557	1	t	0
3621	1557	9	t	0
3622	1558	5	t	0
3623	1558	8	t	0
3624	1558	6	t	0.299999999999999989
3625	1559	2	t	0
3626	1559	4	t	0
3627	1560	8	t	0
3628	1560	3	t	0
3629	1560	1	t	0.299999999999999989
3630	1561	1	t	0
3631	1561	5	t	0
3632	1562	7	t	0
3633	1562	4	t	0
3634	1563	5	t	0
3635	1563	6	t	0
3636	1563	3	t	0.299999999999999989
3637	1564	2	t	0
3638	1564	7	t	0.25
3639	1565	2	t	0
3640	1565	8	t	0
3641	1566	4	t	0
3642	1566	8	t	0
3643	1566	3	t	0.299999999999999989
3644	1567	9	t	0
3645	1567	4	t	0
3646	1568	2	t	0
3647	1568	5	t	0
3648	1569	3	t	0
3649	1569	9	t	0
3650	1570	7	t	0
3651	1570	5	t	0
3652	1571	6	t	0
3653	1571	7	t	0
3654	1571	4	t	0.299999999999999989
3655	1572	8	t	0
3656	1572	4	t	0
3657	1573	6	t	0
3658	1573	2	t	0
3659	1574	2	t	0
3660	1574	8	t	0.25
3661	1575	4	t	0
3662	1575	3	t	0
3663	1576	8	t	0
3664	1576	2	t	0
3665	1576	7	t	0.5
3666	1577	2	t	0
3667	1577	1	t	0
3668	1578	3	t	0
3669	1578	6	t	0
3670	1578	4	t	0.299999999999999989
3671	1579	7	t	0
3672	1579	6	t	0
3673	1580	5	t	0
3674	1580	6	t	0
3675	1581	2	t	0
3676	1581	9	t	0
3677	1582	8	t	0
3678	1582	2	t	0
3679	1583	6	t	0
3680	1583	2	t	0
3681	1584	4	t	0
3682	1584	9	t	0
3683	1584	7	t	0.299999999999999989
3684	1585	7	t	0
3685	1585	4	t	0
3686	1586	9	t	0
3687	1586	2	t	0
3688	1587	5	t	0
3689	1587	4	t	0
3690	1587	7	t	0.299999999999999989
3691	1588	9	t	0
3692	1588	7	t	0
3693	1589	3	t	0
3694	1589	6	t	0
3695	1590	8	t	0
3696	1590	4	t	0
3697	1591	6	t	0
3698	1591	8	t	0.25
3699	1591	7	t	0.299999999999999989
3700	1592	3	t	0
3701	1592	5	t	0
3702	1592	7	t	0.299999999999999989
3703	1593	7	t	0
3704	1593	9	t	0
3705	1594	4	t	0
3706	1594	9	t	0
3707	1595	5	t	0
3708	1595	1	t	0
3709	1595	8	t	0.299999999999999989
3710	1596	1	t	0
3711	1596	7	t	0
3712	1596	2	t	0.5
3713	1597	3	t	0
3714	1597	5	t	0
3715	1597	4	t	0.299999999999999989
3716	1598	6	t	0
3717	1598	5	t	0
3718	1598	2	t	0.5
3719	1599	7	t	0
3720	1599	9	t	0
3721	1600	4	t	0
3722	1600	9	t	0
3723	1601	3	t	0
3724	1601	2	t	0
3725	1602	6	t	0
3726	1602	9	t	0
3727	1603	1	t	0
3728	1603	5	t	0.25
3729	1604	2	t	0
3730	1604	9	t	0
3731	1605	2	t	0
3732	1605	9	t	0.25
3733	1606	6	t	0
3734	1606	7	t	0
3735	1606	2	t	0.5
3736	1607	2	t	0
3737	1607	8	t	0.25
3738	1608	2	t	0
3739	1608	9	t	0
3740	1608	1	t	0.299999999999999989
3741	1609	2	t	0
3742	1609	3	t	0
3743	1610	3	t	0
3744	1610	2	t	0
3745	1611	7	t	0
3746	1611	2	t	0
3747	1612	6	t	0
3748	1612	9	t	0.25
3749	1613	5	t	0
3750	1613	8	t	0
3751	1614	8	t	0
3752	1614	3	t	0
3753	1615	2	t	0
3754	1615	6	t	0
3755	1615	7	t	0.299999999999999989
3756	1616	5	t	0
3757	1616	6	t	0
3758	1616	1	t	0.299999999999999989
3759	1617	2	t	0
3760	1617	6	t	0
3761	1618	6	t	0
3762	1618	2	t	0
3763	1619	2	t	0
3764	1619	8	t	0
3765	1620	5	t	0
3766	1620	6	t	0.25
3767	1621	3	t	0
3768	1621	1	t	0
3769	1622	6	t	0
3770	1622	7	t	0
3771	1623	4	t	0
3772	1623	6	t	0.25
3773	1624	6	t	0
3774	1624	2	t	0
3775	1624	9	t	0.299999999999999989
3776	1625	2	t	0
3777	1625	4	t	0
3778	1626	7	t	0
3779	1626	5	t	0
3780	1627	6	t	0
3781	1627	9	t	0
3782	1627	7	t	0.299999999999999989
3783	1628	2	t	0
3784	1628	7	t	0
3785	1629	8	t	0
3786	1629	1	t	0
3787	1630	4	t	0
3788	1630	2	t	0
3789	1630	3	t	0.299999999999999989
3790	1631	8	t	0
3791	1631	2	t	0
3792	1632	2	t	0
3793	1632	9	t	0
3794	1632	5	t	0.299999999999999989
3795	1633	3	t	0
3796	1633	7	t	0
3797	1634	7	t	0
3798	1634	6	t	0
3799	1634	9	t	0.299999999999999989
3800	1635	6	t	0
3801	1635	8	t	0
3802	1636	1	t	0
3803	1636	6	t	0
3804	1637	5	t	0
3805	1637	3	t	0
3806	1638	6	t	0
3807	1638	9	t	0
3808	1639	8	t	0
3809	1639	9	t	0.25
3810	1640	5	t	0
3811	1640	3	t	0
3812	1641	8	t	0
3813	1641	9	t	0.25
3814	1642	2	t	0
3815	1642	8	t	0.25
3816	1642	4	t	0.299999999999999989
3817	1643	5	t	0
3818	1643	4	t	0
3819	1644	2	t	0
3820	1644	5	t	0
3821	1645	3	t	0
3822	1645	8	t	0.25
3823	1645	1	t	0.5
3824	1646	5	t	0
3825	1646	3	t	0
3826	1647	6	t	0
3827	1647	8	t	0
3828	1648	3	t	0
3829	1648	6	t	0
3830	1649	4	t	0
3831	1649	5	t	0
3832	1650	6	t	0
3833	1650	4	t	0
3834	1651	7	t	0
3835	1651	4	t	0
3836	1652	8	t	0
3837	1652	2	t	0
3838	1653	1	t	0
3839	1653	5	t	0
3840	1653	4	t	0.5
3841	1654	6	t	0
3842	1654	2	t	0
3843	1655	3	t	0
3844	1655	1	t	0
3845	1656	2	t	0
3846	1656	7	t	0
3847	1657	9	t	0
3848	1657	5	t	0.25
3849	1657	2	t	0.299999999999999989
3850	1658	6	t	0
3851	1658	3	t	0
3852	1659	9	t	0
3853	1659	3	t	0
3854	1660	9	t	0
3855	1660	1	t	0
3856	1661	7	t	0
3857	1661	3	t	0.25
3858	1662	3	t	0
3859	1662	7	t	0
3860	1663	9	t	0
3861	1663	6	t	0.25
3862	1664	6	t	0
3863	1664	1	t	0
3864	1665	8	t	0
3865	1665	2	t	0
3866	1665	3	t	0.299999999999999989
3867	1666	6	t	0
3868	1666	1	t	0
3869	1667	4	t	0
3870	1667	6	t	0.25
3871	1668	3	t	0
3872	1668	7	t	0
3873	1669	9	t	0
3874	1669	6	t	0
3875	1670	5	t	0
3876	1670	7	t	0
3877	1671	8	t	0
3878	1671	9	t	0
3879	1671	7	t	0.299999999999999989
3880	1672	7	t	0
3881	1672	8	t	0
3882	1673	5	t	0
3883	1673	3	t	0
3884	1673	1	t	0.299999999999999989
3885	1674	2	t	0
3886	1674	8	t	0
3887	1675	1	t	0
3888	1675	8	t	0
3889	1675	5	t	0.299999999999999989
3890	1676	3	t	0
3891	1676	6	t	0
3892	1677	2	t	0
3893	1677	4	t	0
3894	1677	8	t	0.299999999999999989
3895	1678	9	t	0
3896	1678	1	t	0
3897	1679	6	t	0
3898	1679	8	t	0
3899	1680	6	t	0
3900	1680	1	t	0.25
3901	1681	3	t	0
3902	1681	7	t	0.25
3903	1682	9	t	0
3904	1682	4	t	0
3905	1683	1	t	0
3906	1683	3	t	0
3907	1684	4	t	0
3908	1684	1	t	0
3909	1684	2	t	0.299999999999999989
3910	1685	9	t	0
3911	1685	2	t	0
3912	1686	2	t	0
3913	1686	7	t	0
3914	1687	8	t	0
3915	1687	2	t	0
3916	1688	4	t	0
3917	1688	7	t	0
3918	1689	4	t	0
3919	1689	3	t	0
3920	1690	1	t	0
3921	1690	2	t	0
3922	1691	6	t	0
3923	1691	3	t	0
3924	1692	3	t	0
3925	1692	9	t	0
3926	1693	9	t	0
3927	1693	5	t	0
3928	1693	4	t	0.299999999999999989
3929	1694	1	t	0
3930	1694	6	t	0
3931	1695	1	t	0
3932	1695	2	t	0
3933	1695	5	t	0.299999999999999989
3934	1696	9	t	0
3935	1696	6	t	0
3936	1697	6	t	0
3937	1697	9	t	0
3938	1698	6	t	0
3939	1698	1	t	0.25
3940	1699	5	t	0
3941	1699	1	t	0
3942	1699	4	t	0.299999999999999989
3943	1700	3	t	0
3944	1700	2	t	0
3945	1700	4	t	0.299999999999999989
3946	1701	2	t	0
3947	1701	3	t	0
3948	1702	2	t	0
3949	1702	8	t	0.25
3950	1703	8	t	0
3951	1703	3	t	0
3952	1704	7	t	0
3953	1704	3	t	0
3954	1705	1	t	0
3955	1705	6	t	0
3956	1706	8	t	0
3957	1706	1	t	0
3958	1707	7	t	0
3959	1707	9	t	0
3960	1707	6	t	0.299999999999999989
3961	1708	8	t	0
3962	1708	1	t	0.25
3963	1708	9	t	0.299999999999999989
3964	1709	5	t	0
3965	1709	8	t	0
3966	1710	3	t	0
3967	1710	7	t	0
3968	1711	6	t	0
3969	1711	4	t	0
3970	1712	4	t	0
3971	1712	9	t	0
3972	1713	7	t	0
3973	1713	8	t	0
3974	1713	9	t	0.5
3975	1714	1	t	0
3976	1714	8	t	0
3977	1715	9	t	0
3978	1715	2	t	0
3979	1715	6	t	0.299999999999999989
3980	1716	3	t	0
3981	1716	8	t	0
3982	1717	7	t	0
3983	1717	8	t	0.25
3984	1718	6	t	0
3985	1718	4	t	0.25
3986	1719	7	t	0
3987	1719	2	t	0
3988	1720	5	t	0
3989	1720	8	t	0
3990	1720	1	t	0.299999999999999989
3991	1721	9	t	0
3992	1721	5	t	0
3993	1722	5	t	0
3994	1722	1	t	0
3995	1722	8	t	0.5
3996	1723	8	t	0
3997	1723	3	t	0
3998	1724	4	t	0
3999	1724	7	t	0
4000	1725	9	t	0
4001	1725	8	t	0
4002	1726	3	t	0
4003	1726	8	t	0
4004	1726	6	t	0.299999999999999989
4005	1727	8	t	0
4006	1727	3	t	0
4007	1728	3	t	0
4008	1728	5	t	0
4009	1729	4	t	0
4010	1729	6	t	0
4011	1730	2	t	0
4012	1730	6	t	0
4013	1731	4	t	0
4014	1731	1	t	0
4015	1731	7	t	0.299999999999999989
4016	1732	6	t	0
4017	1732	1	t	0
4018	1732	9	t	0.5
4019	1733	6	t	0
4020	1733	7	t	0
4021	1734	2	t	0
4022	1734	1	t	0
4023	1734	5	t	0.5
4024	1735	8	t	0
4025	1735	3	t	0
4026	1735	1	t	0.299999999999999989
4027	1736	5	t	0
4028	1736	9	t	0
4029	1737	6	t	0
4030	1737	3	t	0
4031	1738	6	t	0
4032	1738	3	t	0
4033	1738	9	t	0.299999999999999989
4034	1739	4	t	0
4035	1739	1	t	0
4036	1740	5	t	0
4037	1740	1	t	0
4038	1741	7	t	0
4039	1741	3	t	0.25
4040	1742	2	t	0
4041	1742	1	t	0
4042	1742	6	t	0.299999999999999989
4043	1743	1	t	0
4044	1743	6	t	0
4045	1743	8	t	0.299999999999999989
4046	1744	5	t	0
4047	1744	3	t	0
4048	1744	2	t	0.299999999999999989
4049	1745	7	t	0
4050	1745	2	t	0
4051	1745	5	t	0.5
4052	1746	5	t	0
4053	1746	7	t	0
4054	1746	6	t	0.299999999999999989
4055	1747	6	t	0
4056	1747	8	t	0
4057	1747	3	t	0.299999999999999989
4058	1748	9	t	0
4059	1748	7	t	0
4060	1748	8	t	0.299999999999999989
4061	1749	9	t	0
4062	1749	8	t	0
4063	1750	3	t	0
4064	1750	5	t	0
4065	1750	8	t	0.299999999999999989
4066	1751	7	t	0
4067	1751	5	t	0
4068	1751	4	t	0.299999999999999989
4069	1752	6	t	0
4070	1752	9	t	0.25
4071	1753	6	t	0
4072	1753	3	t	0
4073	1753	5	t	0.299999999999999989
4074	1754	6	t	0
4075	1754	4	t	0
4076	1755	7	t	0
4077	1755	1	t	0
4078	1756	6	t	0
4079	1756	2	t	0
4080	1757	9	t	0
4081	1757	8	t	0
4082	1758	6	t	0
4083	1758	8	t	0
4084	1759	8	t	0
4085	1759	6	t	0
4086	1759	1	t	0.299999999999999989
4087	1760	2	t	0
4088	1760	8	t	0
4089	1760	9	t	0.299999999999999989
4090	1761	1	t	0
4091	1761	7	t	0
4092	1762	8	t	0
4093	1762	3	t	0
4094	1763	1	t	0
4095	1763	4	t	0
4096	1764	2	t	0
4097	1764	8	t	0
4098	1764	6	t	0.299999999999999989
4099	1765	2	t	0
4100	1765	5	t	0.25
4101	1765	8	t	0.299999999999999989
4102	1766	8	t	0
4103	1766	4	t	0
4104	1767	3	t	0
4105	1767	4	t	0
4106	1768	3	t	0
4107	1768	2	t	0
4108	1768	7	t	0.5
4109	1769	1	t	0
4110	1769	7	t	0
4111	1769	5	t	0.299999999999999989
4112	1770	9	t	0
4113	1770	2	t	0
4114	1771	7	t	0
4115	1771	5	t	0.25
4116	1771	8	t	0.299999999999999989
4117	1772	5	t	0
4118	1772	3	t	0
4119	1773	7	t	0
4120	1773	9	t	0
4121	1773	8	t	0.299999999999999989
4122	1774	8	t	0
4123	1774	3	t	0
4124	1774	6	t	0.299999999999999989
4125	1775	7	t	0
4126	1775	9	t	0
4127	1775	8	t	0.299999999999999989
4128	1776	7	t	0
4129	1776	9	t	0
4130	1776	1	t	0.299999999999999989
4131	1777	8	t	0
4132	1777	1	t	0
4133	1777	4	t	0.299999999999999989
4134	1778	4	t	0
4135	1778	8	t	0
4136	1778	9	t	0.5
4137	1779	9	t	0
4138	1779	3	t	0
4139	1780	5	t	0
4140	1780	9	t	0
4141	1781	5	t	0
4142	1781	7	t	0
4143	1782	3	t	0
4144	1782	5	t	0.25
4145	1783	9	t	0
4146	1783	8	t	0
4147	1783	2	t	0.299999999999999989
4148	1784	8	t	0
4149	1784	1	t	0
4150	1785	7	t	0
4151	1785	1	t	0
4152	1786	3	t	0
4153	1786	5	t	0
4154	1786	9	t	0.299999999999999989
4155	1787	5	t	0
4156	1787	7	t	0
4157	1788	2	t	0
4158	1788	6	t	0
4159	1788	8	t	0.299999999999999989
4160	1789	8	t	0
4161	1789	5	t	0
4162	1789	2	t	0.299999999999999989
4163	1790	1	t	0
4164	1790	5	t	0
4165	1790	9	t	0.299999999999999989
4166	1791	6	t	0
4167	1791	8	t	0
4168	1792	6	t	0
4169	1792	9	t	0
4170	1793	6	t	0
4171	1793	7	t	0.25
4172	1794	5	t	0
4173	1794	2	t	0
4174	1794	7	t	0.5
4175	1795	4	t	0
4176	1795	1	t	0.25
4177	1795	2	t	0.299999999999999989
4178	1796	8	t	0
4179	1796	6	t	0
4180	1797	8	t	0
4181	1797	3	t	0
4182	1798	7	t	0
4183	1798	1	t	0
4184	1799	3	t	0
4185	1799	7	t	0
4186	1800	4	t	0
4187	1800	2	t	0
4188	1801	9	t	0
4189	1801	5	t	0
4190	1802	2	t	0
4191	1802	9	t	0
4192	1803	9	t	0
4193	1803	7	t	0
4194	1804	7	t	0
4195	1804	6	t	0
4196	1805	5	t	0
4197	1805	2	t	0
4198	1806	6	t	0
4199	1806	7	t	0
4200	1807	2	t	0
4201	1807	9	t	0
4202	1808	5	t	0
4203	1808	1	t	0
4204	1809	9	t	0
4205	1809	7	t	0
4206	1809	1	t	0.5
4207	1810	5	t	0
4208	1810	3	t	0
4209	1811	2	t	0
4210	1811	7	t	0
4211	1812	4	t	0
4212	1812	9	t	0
4213	1812	8	t	0.299999999999999989
4214	1813	8	t	0
4215	1813	6	t	0
4216	1814	2	t	0
4217	1814	1	t	0
4218	1815	1	t	0
4219	1815	4	t	0
4220	1815	5	t	0.299999999999999989
4221	1816	2	t	0
4222	1816	5	t	0
4223	1816	3	t	0.299999999999999989
4224	1817	4	t	0
4225	1817	7	t	0
4226	1818	4	t	0
4227	1818	7	t	0
4228	1818	8	t	0.299999999999999989
4229	1819	7	t	0
4230	1819	6	t	0
4231	1820	8	t	0
4232	1820	2	t	0
4233	1821	6	t	0
4234	1821	9	t	0
4235	1821	2	t	0.299999999999999989
4236	1822	9	t	0
4237	1822	4	t	0.25
4238	1823	7	t	0
4239	1823	2	t	0
4240	1824	4	t	0
4241	1824	5	t	0
4242	1824	7	t	0.5
4243	1825	6	t	0
4244	1825	7	t	0.25
4245	1826	1	t	0
4246	1826	6	t	0
4247	1827	2	t	0
4248	1827	5	t	0
4249	1827	9	t	0.299999999999999989
4250	1828	2	t	0
4251	1828	3	t	0
4252	1829	3	t	0
4253	1829	1	t	0
4254	1829	2	t	0.299999999999999989
4255	1830	5	t	0
4256	1830	1	t	0
4257	1831	3	t	0
4258	1831	4	t	0
4259	1832	5	t	0
4260	1832	6	t	0
4261	1833	1	t	0
4262	1833	6	t	0
4263	1834	9	t	0
4264	1834	3	t	0
4265	1834	5	t	0.299999999999999989
4266	1835	4	t	0
4267	1835	2	t	0
4268	1836	9	t	0
4269	1836	1	t	0
4270	1836	6	t	0.299999999999999989
4271	1837	2	t	0
4272	1837	7	t	0.25
4273	1838	1	t	0
4274	1838	6	t	0
4275	1838	7	t	0.299999999999999989
4276	1839	7	t	0
4277	1839	5	t	0
4278	1839	2	t	0.299999999999999989
4279	1840	8	t	0
4280	1840	1	t	0
4281	1841	3	t	0
4282	1841	7	t	0.25
4283	1842	4	t	0
4284	1842	7	t	0
4285	1843	9	t	0
4286	1843	2	t	0.25
4287	1844	9	t	0
4288	1844	5	t	0
4289	1845	2	t	0
4290	1845	5	t	0
4291	1846	2	t	0
4292	1846	6	t	0.25
4293	1846	1	t	0.299999999999999989
4294	1847	7	t	0
4295	1847	8	t	0
4296	1848	5	t	0
4297	1848	8	t	0.25
4298	1848	3	t	0.299999999999999989
4299	1849	7	t	0
4300	1849	1	t	0.25
4301	1850	1	t	0
4302	1850	7	t	0
4303	1850	3	t	0.299999999999999989
4304	1851	4	t	0
4305	1851	5	t	0
4306	1852	7	t	0
4307	1852	9	t	0
4308	1852	8	t	0.299999999999999989
4309	1853	5	t	0
4310	1853	9	t	0
4311	1853	4	t	0.5
4312	1854	4	t	0
4313	1854	6	t	0.25
4314	1855	9	t	0
4315	1855	6	t	0
4316	1856	4	t	0
4317	1856	2	t	0
4318	1857	3	t	0
4319	1857	7	t	0
4320	1857	9	t	0.299999999999999989
4321	1858	2	t	0
4322	1858	9	t	0
4323	1859	1	t	0
4324	1859	4	t	0
4325	1859	7	t	0.299999999999999989
4326	1860	2	t	0
4327	1860	3	t	0
4328	1861	5	t	0
4329	1861	6	t	0
4330	1862	5	t	0
4331	1862	4	t	0
4332	1863	3	t	0
4333	1863	7	t	0
4334	1864	4	t	0
4335	1864	3	t	0
4336	1865	9	t	0
4337	1865	8	t	0
4338	1866	8	t	0
4339	1866	3	t	0
4340	1867	4	t	0
4341	1867	9	t	0
4342	1868	4	t	0
4343	1868	1	t	0
4344	1868	5	t	0.299999999999999989
4345	1869	5	t	0
4346	1869	9	t	0
4347	1870	9	t	0
4348	1870	2	t	0
4349	1871	3	t	0
4350	1871	5	t	0
4351	1871	7	t	0.299999999999999989
4352	1872	7	t	0
4353	1872	3	t	0
4354	1872	6	t	0.299999999999999989
4355	1873	6	t	0
4356	1873	7	t	0.25
4357	1874	2	t	0
4358	1874	9	t	0.25
4359	1875	3	t	0
4360	1875	2	t	0
4361	1876	9	t	0
4362	1876	6	t	0
4363	1877	8	t	0
4364	1877	2	t	0
4365	1877	7	t	0.299999999999999989
4366	1878	8	t	0
4367	1878	2	t	0
4368	1879	5	t	0
4369	1879	7	t	0
4370	1880	3	t	0
4371	1880	8	t	0
4372	1881	3	t	0
4373	1881	6	t	0
4374	1882	5	t	0
4375	1882	6	t	0
4376	1882	7	t	0.299999999999999989
4377	1883	7	t	0
4378	1883	9	t	0
4379	1884	2	t	0
4380	1884	6	t	0
4381	1884	3	t	0.299999999999999989
4382	1885	9	t	0
4383	1885	4	t	0
4384	1886	7	t	0
4385	1886	1	t	0
4386	1887	5	t	0
4387	1887	4	t	0.25
4388	1888	1	t	0
4389	1888	8	t	0
4390	1889	2	t	0
4391	1889	7	t	0
4392	1890	5	t	0
4393	1890	4	t	0
4394	1891	6	t	0
4395	1891	7	t	0.25
4396	1892	5	t	0
4397	1892	7	t	0
4398	1892	8	t	0.299999999999999989
4399	1893	9	t	0
4400	1893	7	t	0.25
4401	1894	3	t	0
4402	1894	9	t	0
4403	1895	8	t	0
4404	1895	7	t	0
4405	1896	1	t	0
4406	1896	5	t	0
4407	1897	5	t	0
4408	1897	6	t	0
4409	1898	7	t	0
4410	1898	4	t	0
4411	1899	8	t	0
4412	1899	6	t	0
4413	1899	5	t	0.299999999999999989
4414	1900	3	t	0
4415	1900	8	t	0
4416	1901	7	t	0
4417	1901	8	t	0
4418	1901	4	t	0.299999999999999989
4419	1902	3	t	0
4420	1902	9	t	0
4421	1903	2	t	0
4422	1903	5	t	0
4423	1903	3	t	0.299999999999999989
4424	1904	6	t	0
4425	1904	4	t	0
4426	1905	9	t	0
4427	1905	4	t	0
4428	1905	7	t	0.299999999999999989
4429	1906	6	t	0
4430	1906	2	t	0
4431	1907	1	t	0
4432	1907	5	t	0
4433	1908	3	t	0
4434	1908	5	t	0
4435	1909	7	t	0
4436	1909	1	t	0
4437	1910	8	t	0
4438	1910	9	t	0
4439	1911	6	t	0
4440	1911	8	t	0
4441	1912	7	t	0
4442	1912	6	t	0
4443	1913	6	t	0
4444	1913	8	t	0
4445	1913	5	t	0.299999999999999989
4446	1914	3	t	0
4447	1914	8	t	0
4448	1915	7	t	0
4449	1915	6	t	0
4450	1915	1	t	0.299999999999999989
4451	1916	1	t	0
4452	1916	7	t	0
4453	1916	9	t	0.299999999999999989
4454	1917	1	t	0
4455	1917	3	t	0
4456	1918	6	t	0
4457	1918	4	t	0
4458	1918	9	t	0.5
4459	1919	5	t	0
4460	1919	7	t	0
4461	1919	9	t	0.299999999999999989
4462	1920	1	t	0
4463	1920	2	t	0.25
4464	1921	6	t	0
4465	1921	5	t	0
4466	1921	2	t	0.299999999999999989
4467	1922	3	t	0
4468	1922	2	t	0.25
4469	1923	5	t	0
4470	1923	6	t	0
4471	1924	5	t	0
4472	1924	6	t	0
4473	1924	3	t	0.299999999999999989
4474	1925	7	t	0
4475	1925	1	t	0.25
4476	1926	2	t	0
4477	1926	1	t	0
4478	1927	8	t	0
4479	1927	6	t	0
4480	1928	5	t	0
4481	1928	3	t	0
4482	1928	7	t	0.299999999999999989
4483	1929	8	t	0
4484	1929	1	t	0.25
4485	1930	7	t	0
4486	1930	1	t	0
4487	1931	8	t	0
4488	1931	4	t	0
4489	1932	1	t	0
4490	1932	6	t	0
4491	1932	8	t	0.299999999999999989
4492	1933	8	t	0
4493	1933	5	t	0
4494	1934	3	t	0
4495	1934	6	t	0
4496	1935	5	t	0
4497	1935	8	t	0
4498	1935	9	t	0.299999999999999989
4499	1936	1	t	0
4500	1936	5	t	0
4501	1937	1	t	0
4502	1937	2	t	0
4503	1937	9	t	0.299999999999999989
4504	1938	4	t	0
4505	1938	1	t	0
4506	1938	3	t	0.5
4507	1939	6	t	0
4508	1939	5	t	0
4509	1940	7	t	0
4510	1940	4	t	0
4511	1940	3	t	0.299999999999999989
4512	1941	8	t	0
4513	1941	7	t	0.25
4514	1941	6	t	0.299999999999999989
4515	1942	6	t	0
4516	1942	3	t	0
4517	1943	3	t	0
4518	1943	6	t	0
4519	1944	7	t	0
4520	1944	1	t	0
4521	1945	5	t	0
4522	1945	8	t	0
4523	1946	9	t	0
4524	1946	1	t	0
4525	1946	6	t	0.299999999999999989
4526	1947	2	t	0
4527	1947	8	t	0.25
4528	1948	4	t	0
4529	1948	3	t	0
4530	1949	5	t	0
4531	1949	6	t	0
4532	1950	2	t	0
\.


--
-- Name: treatments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('treatments_id_seq', 4532, true);


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY users (id, first_name, last_name, role, username, password_digest, active) FROM stdin;
1	Doctor	Cuke	vet	vet	$2a$10$hxpzDIbPg2nI3i6cBQT17u5ioL/nDjLiC8I/lV.8TE5/eav5xO0YK	t
\.


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('users_id_seq', 1, true);


--
-- Data for Name: visit_medicines; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY visit_medicines (id, visit_id, medicine_id, units_given, discount) FROM stdin;
1	2	9	300	0
2	4	2	200	0
3	4	9	300	0.5
4	5	2	300	0.5
5	6	2	300	0
6	7	8	100	0
7	10	6	100	0
8	10	9	200	0.5
9	15	5	100	0
10	15	6	300	0
11	18	8	100	0
12	18	5	200	0
13	22	2	100	0
14	23	9	100	0
15	23	6	300	0
16	24	9	100	0
17	25	9	200	0
18	25	9	200	0
19	27	6	300	0
20	27	6	200	0
21	32	2	200	0
22	33	10	200	0
23	33	4	300	0
24	35	9	300	0
25	37	2	100	0
26	38	5	100	0
27	38	2	300	0
28	39	9	300	0
29	39	2	300	0
30	40	6	200	0
31	43	2	200	0
32	43	2	200	0
33	44	5	300	0.5
34	44	10	200	0
35	47	5	300	0
36	47	9	300	0.5
37	49	4	100	0
38	49	10	200	0
39	50	2	200	0
40	50	5	300	0
41	51	10	300	0
42	51	2	300	0
43	52	5	100	0
44	52	2	300	0
45	53	9	200	0
46	54	6	200	0
47	55	6	300	0
48	55	6	200	0
49	57	9	100	0
50	58	9	300	0
51	58	9	200	0
52	59	6	200	0
53	60	6	300	0
54	61	6	100	0
55	63	8	300	0
56	64	1	100	0
57	64	3	100	0
58	66	6	300	0
59	67	6	300	0
60	68	2	100	0
61	68	4	200	0
62	70	3	300	0
63	71	9	100	0
64	74	5	200	0
65	76	1	100	0
66	77	2	200	0
67	77	6	100	0
68	78	2	300	0
69	78	2	200	0
70	81	2	200	0
71	81	2	100	0
72	82	9	200	0
73	83	2	300	0
74	84	9	300	0
75	86	2	300	0
76	86	6	100	0
77	90	2	200	0.5
78	91	9	300	0
79	93	6	300	0
80	96	2	300	0
81	96	9	200	0
82	97	2	200	0
83	97	9	100	0
84	98	6	200	0
85	98	9	300	0
86	100	6	200	0
87	100	2	100	0
88	101	9	100	0
89	101	9	200	0
90	103	6	200	0
91	104	9	100	0
92	104	2	300	0
93	106	6	100	0
94	112	6	200	0
95	114	2	200	0
96	114	9	200	0
97	118	9	100	0
98	118	5	200	0
99	119	1	100	0
100	120	1	300	0
101	121	1	200	0
102	123	1	200	0
103	124	6	300	0
104	124	5	300	0
105	128	7	300	0
106	128	7	100	0
107	130	6	300	0
108	134	7	200	0
109	136	6	200	0
110	136	6	200	0
111	138	6	200	0
112	141	9	200	0
113	141	9	300	0
114	142	2	300	0
115	142	2	100	0
116	146	2	200	0
117	148	2	100	0
118	148	9	300	0
119	151	2	300	0
120	153	4	200	0
121	153	8	200	0
122	157	9	100	0
123	157	9	300	0
124	158	2	200	0
125	159	2	200	0
126	159	1	300	0
127	160	4	200	0.5
128	161	3	100	0
129	161	8	100	0
130	162	5	200	0
131	164	5	100	0
132	168	9	300	0
133	168	4	100	0
134	172	1	200	0
135	175	6	200	0
136	176	6	300	0
137	177	6	100	0
138	178	6	100	0
139	179	2	100	0
140	183	9	100	0
141	183	6	200	0
142	187	9	200	0
143	187	6	100	0.5
144	193	3	200	0
145	193	5	100	0
146	194	1	300	0
147	195	5	300	0
148	195	4	100	0
149	196	3	100	0
150	196	9	100	0
151	197	8	200	0
152	198	1	100	0
153	198	8	300	0
154	203	6	100	0
155	204	9	300	0
156	206	9	300	0
157	208	2	300	0.5
158	208	9	300	0
159	211	6	100	0
160	214	6	200	0
161	214	9	300	0.5
162	215	9	300	0
163	215	9	200	0
164	216	2	300	0
165	219	9	300	0
166	221	9	200	0
167	222	6	200	0
168	225	2	200	0
169	228	9	100	0
170	228	2	200	0
171	229	2	200	0
172	230	2	200	0
173	230	6	100	0
174	233	2	200	0
175	237	9	200	0
176	238	2	200	0
177	239	2	200	0
178	239	9	100	0
179	240	6	200	0
180	241	9	300	0
181	242	9	200	0
182	242	2	300	0
183	243	6	200	0
184	243	9	100	0
185	245	9	100	0
186	246	9	100	0
187	247	2	300	0
188	248	2	200	0
189	248	2	200	0
190	249	2	200	0
191	250	2	300	0
192	251	6	300	0
193	256	2	300	0
194	256	9	100	0
195	257	4	200	0
196	257	5	200	0
197	258	1	100	0
198	259	4	100	0
199	260	9	200	0.5
200	260	4	100	0
201	261	1	200	0
202	264	5	200	0
203	264	8	200	0
204	265	4	100	0
205	265	9	200	0
206	266	6	300	0
207	273	2	200	0
208	273	6	300	0
209	274	9	200	0
210	276	6	200	0
211	277	2	100	0
212	277	10	100	0
213	281	7	200	0
214	282	2	100	0
215	285	6	300	0
216	285	2	300	0
217	286	6	100	0.5
218	287	2	100	0
219	287	2	100	0
220	288	2	200	0
221	290	2	200	0
222	290	2	300	0
223	291	6	200	0
224	292	9	200	0
225	292	2	100	0
226	297	2	300	0
227	298	9	300	0
228	299	2	300	0
229	299	9	200	0.5
230	300	2	300	0
231	300	2	100	0
232	301	6	100	0
233	302	9	200	0
234	305	2	300	0
235	307	7	100	0
236	307	2	100	0
237	309	2	100	0
238	312	7	100	0
239	313	7	300	0
240	313	7	300	0
241	314	6	300	0
242	314	7	200	0
243	316	6	200	0.5
244	316	6	200	0.5
245	317	7	200	0
246	317	6	200	0
247	320	9	300	0
248	326	6	100	0
249	327	6	300	0
250	329	9	100	0
251	331	2	100	0.5
252	331	2	100	0
253	334	2	200	0
254	334	9	300	0
255	337	6	300	0
256	341	2	200	0
257	341	5	300	0
258	342	3	100	0
259	342	3	300	0
260	344	8	100	0
261	345	8	100	0
262	345	8	300	0
263	347	9	100	0
264	347	1	300	0
265	351	7	100	0
266	352	6	300	0
267	352	2	200	0
268	353	7	300	0
269	355	6	300	0
270	358	7	300	0
271	360	7	300	0.5
272	360	7	200	0
273	361	2	200	0
274	361	2	300	0
275	362	7	300	0
276	362	6	200	0
277	364	6	100	0
278	364	7	300	0
279	365	5	200	0
280	365	2	100	0
281	366	9	100	0
282	367	4	100	0
283	367	10	200	0
284	368	6	100	0
285	369	9	100	0
286	369	5	100	0
287	370	5	100	0
288	370	6	300	0
289	375	6	200	0
290	375	2	200	0
291	378	9	200	0
292	378	9	200	0
293	381	7	100	0
294	382	2	300	0
295	382	7	100	0
296	384	6	100	0
297	384	2	100	0
298	387	6	200	0
299	391	2	200	0
300	391	7	100	0
301	393	6	300	0
302	394	2	300	0
303	395	9	100	0
304	396	6	300	0
305	397	9	300	0
306	402	6	300	0
307	402	2	100	0
308	403	2	100	0
309	403	9	300	0
310	405	9	300	0
311	405	6	100	0
312	406	2	100	0
313	407	2	200	0
314	408	6	200	0
315	408	6	100	0
316	409	9	300	0
317	411	2	100	0
318	411	2	200	0
319	412	2	300	0
320	412	6	100	0
321	418	9	300	0
322	418	6	100	0
323	422	2	300	0
324	422	6	100	0
325	423	6	200	0
326	423	2	100	0
327	424	2	100	0
328	425	6	100	0
329	428	6	300	0
330	428	7	100	0
331	430	6	100	0
332	431	2	200	0
333	432	6	200	0
334	432	6	200	0
335	434	6	200	0
336	437	9	100	0
337	439	9	300	0
338	439	2	200	0
339	440	6	100	0
340	440	6	300	0
341	441	2	200	0
342	441	6	200	0
343	442	6	300	0
344	443	9	300	0
345	444	6	200	0.5
346	447	2	300	0
347	447	2	200	0
348	450	6	300	0.5
349	450	9	200	0
350	455	2	200	0
351	455	6	100	0
352	456	6	200	0
353	458	6	100	0
354	458	6	100	0
355	462	9	200	0
356	462	9	200	0
357	465	2	200	0
358	465	6	200	0
359	467	10	200	0.5
360	468	6	300	0
361	469	2	200	0
362	470	10	200	0
363	471	6	200	0
364	474	2	100	0
365	474	6	200	0
366	476	2	300	0
367	479	2	200	0
368	479	2	200	0
369	481	6	200	0
370	481	2	200	0
371	484	2	300	0
372	484	3	300	0
373	485	5	300	0
374	488	9	100	0
375	489	3	100	0
376	490	3	100	0
377	492	3	200	0
378	493	5	100	0
379	494	2	300	0
380	496	2	300	0
381	496	9	100	0
382	497	2	300	0
383	501	2	300	0
384	503	2	100	0
385	504	6	300	0
386	504	6	100	0
387	505	6	300	0
388	506	7	100	0
389	508	6	100	0
390	509	2	300	0
391	514	2	200	0
392	517	2	200	0
393	518	2	100	0
394	518	9	200	0
395	520	2	300	0
396	522	4	200	0
397	523	4	200	0
398	523	2	300	0
399	524	5	100	0
400	524	9	100	0
401	526	1	300	0
402	527	5	200	0
403	527	9	100	0
404	528	8	200	0
405	528	2	200	0.5
406	530	1	100	0
407	531	1	100	0
408	533	3	100	0
409	537	8	200	0
410	539	9	200	0
411	540	6	200	0
412	541	1	300	0
413	544	2	100	0
414	544	9	100	0
415	545	8	100	0
416	545	3	100	0
417	549	2	100	0
418	550	7	300	0
419	550	7	100	0
420	554	2	300	0
421	554	2	100	0
422	556	2	300	0
423	557	6	300	0
424	558	6	300	0
425	561	9	300	0
426	561	6	100	0
427	562	4	300	0
428	563	6	300	0
429	563	10	100	0
430	564	4	300	0
431	565	5	200	0
432	565	6	100	0
433	567	9	200	0
434	567	4	200	0
435	570	4	200	0
436	570	3	100	0
437	575	3	200	0.5
438	575	6	300	0
439	576	1	300	0
440	579	6	200	0.5
441	579	9	100	0
442	580	6	200	0
443	580	3	100	0
444	583	5	300	0
445	585	9	200	0
446	587	2	100	0
447	587	9	200	0
448	589	2	100	0
449	589	6	100	0
450	592	6	300	0
451	592	9	200	0
452	594	2	300	0.5
453	595	6	300	0
454	595	2	100	0
455	597	6	200	0
456	597	6	200	0
457	599	2	100	0
458	601	6	300	0
459	602	2	100	0
460	602	2	100	0
461	603	9	100	0
462	604	9	200	0
463	604	9	200	0
464	609	9	100	0
465	609	9	100	0
466	611	10	300	0
467	612	4	100	0
468	612	4	300	0
469	613	5	300	0
470	613	6	200	0
471	615	6	300	0
472	617	10	300	0
473	617	9	100	0
474	618	9	300	0
475	619	5	100	0
476	619	10	100	0
477	620	9	100	0
478	620	6	100	0
479	625	2	200	0
480	625	6	200	0
481	628	9	100	0
482	628	3	300	0
483	631	6	200	0
484	631	9	100	0
485	632	9	200	0
486	633	2	100	0
487	633	9	200	0
488	634	9	200	0
489	637	2	100	0
490	638	6	300	0
491	639	2	200	0
492	639	2	300	0
493	640	2	200	0
494	640	6	200	0
495	641	4	300	0
496	642	4	200	0
497	642	8	300	0
498	643	8	200	0
499	644	5	300	0
500	646	9	100	0
501	646	2	200	0
502	647	2	300	0
503	648	6	300	0
504	649	2	300	0
505	649	9	300	0
506	652	2	300	0
507	654	2	100	0
508	654	6	300	0
509	656	9	300	0
510	656	2	200	0
511	658	2	100	0
512	658	9	200	0
513	659	9	100	0
514	659	2	100	0
515	660	6	100	0
516	660	6	100	0
517	661	2	100	0
518	661	9	300	0
519	662	9	300	0
520	662	9	200	0
521	663	9	300	0.5
522	663	6	300	0
523	665	2	200	0
524	665	9	300	0.5
525	666	2	100	0
526	667	6	200	0
527	667	2	100	0
528	668	9	100	0
529	668	9	100	0
530	671	2	300	0
531	672	6	300	0
532	672	2	300	0
533	677	5	100	0
534	677	2	200	0
535	680	4	100	0
536	680	8	100	0
537	682	2	100	0
538	683	2	300	0
539	683	1	100	0
540	685	5	100	0
541	692	2	200	0
542	692	4	300	0
543	693	3	100	0.5
544	694	9	200	0
545	698	6	100	0
546	698	9	100	0
547	706	9	200	0
548	706	9	300	0
549	707	2	100	0
550	707	6	300	0
551	711	9	100	0
552	711	6	200	0
553	719	5	200	0.5
554	719	5	200	0
555	720	10	100	0
556	720	4	200	0.5
557	728	2	300	0.5
558	728	9	200	0.5
559	729	6	300	0
560	729	2	300	0
561	730	9	100	0
562	733	6	200	0
563	740	6	200	0
564	741	7	100	0
565	741	7	300	0
566	742	6	300	0.5
567	747	2	300	0
568	747	9	200	0
569	753	9	200	0
570	754	2	200	0
571	754	6	300	0
572	755	9	100	0
573	757	6	200	0
574	757	9	200	0
575	758	9	100	0
576	758	9	200	0.5
577	759	9	300	0
578	760	6	200	0.5
579	762	9	200	0
580	764	2	200	0
581	765	9	300	0
582	767	6	200	0
583	772	2	300	0
584	772	6	200	0
585	773	2	200	0
586	773	9	300	0
587	776	2	300	0
588	776	6	100	0
589	778	6	200	0
590	778	6	300	0
591	779	6	300	0
592	780	2	200	0
593	781	9	100	0
594	783	2	200	0
595	783	2	300	0
596	785	6	300	0
597	786	6	200	0
598	786	7	100	0
599	787	7	200	0
600	787	6	100	0.5
601	788	7	300	0
602	789	2	100	0
603	789	2	200	0
604	790	6	200	0
605	790	2	100	0
606	792	6	100	0
607	795	2	300	0
608	795	6	300	0
609	797	6	100	0
610	797	2	200	0
611	798	2	300	0
612	804	6	300	0
613	806	7	300	0
614	806	6	200	0
615	807	7	100	0
616	810	6	200	0
617	810	2	100	0
618	815	6	200	0
619	819	6	300	0
620	819	2	200	0
621	822	4	300	0
622	824	9	300	0
623	824	6	100	0
624	825	6	200	0
625	826	2	200	0
626	827	2	300	0
627	829	6	100	0
628	829	9	300	0
629	831	2	300	0
630	832	9	100	0
631	832	6	300	0
632	833	6	200	0
633	833	9	100	0
634	837	6	300	0
635	837	6	100	0
636	839	2	300	0
637	839	2	300	0
638	840	2	300	0
639	841	6	300	0
640	842	6	100	0
641	844	6	100	0
642	844	7	100	0
643	850	6	300	0
644	850	9	100	0
645	851	6	200	0.5
646	853	6	300	0
647	853	6	300	0
648	855	6	100	0
649	855	2	300	0
650	858	6	200	0
651	860	2	300	0
652	861	9	200	0
653	864	6	200	0
654	864	9	100	0
655	865	6	200	0
656	865	6	200	0
657	866	5	300	0
658	867	2	300	0
659	868	2	300	0
660	868	6	200	0
661	870	2	300	0
662	870	2	200	0
663	873	6	200	0
664	874	9	300	0
665	874	2	100	0
666	875	6	100	0
667	875	6	200	0.5
668	877	2	300	0
669	877	2	300	0
670	878	2	200	0
671	878	2	300	0
672	879	6	100	0.5
673	880	6	200	0
674	882	2	300	0
675	882	2	200	0
676	883	6	200	0
677	883	9	300	0.5
678	885	6	200	0
679	885	6	200	0
680	887	5	100	0
681	887	4	300	0
682	888	2	200	0
683	888	2	100	0
684	889	10	300	0
685	889	6	100	0
686	894	6	100	0
687	894	5	200	0
688	895	2	100	0
689	895	7	200	0
690	900	9	100	0
691	902	2	100	0
692	902	2	200	0
693	907	6	100	0
694	907	6	300	0
695	909	5	300	0
696	910	9	200	0
697	913	2	300	0
698	914	2	300	0
699	915	9	200	0.5
700	915	6	100	0
701	916	2	200	0
702	917	9	100	0
703	920	9	100	0.5
704	924	9	200	0.5
705	924	6	100	0
706	926	6	100	0
707	930	4	300	0
708	931	2	300	0
709	931	4	200	0
710	936	5	200	0
711	936	4	100	0
712	937	6	300	0
713	937	2	100	0
714	938	9	300	0.5
715	938	2	100	0
716	939	2	300	0
717	939	2	200	0
718	940	6	300	0
719	942	9	200	0
720	944	6	300	0
721	944	9	200	0
722	947	4	100	0
723	947	5	100	0
724	948	9	200	0
725	948	2	100	0
726	950	6	100	0
727	950	6	200	0
728	952	6	200	0
729	953	4	300	0
730	956	9	200	0
731	956	9	200	0
732	957	2	100	0.5
733	957	9	300	0
734	958	2	300	0
735	958	2	200	0
736	959	2	300	0
737	960	9	200	0
738	960	9	200	0
739	962	2	300	0
740	963	6	200	0
741	963	2	100	0
742	965	6	100	0
743	966	6	100	0
744	967	6	100	0
745	970	9	300	0
746	970	9	300	0
747	975	9	100	0
748	981	6	200	0
749	981	6	100	0
750	982	9	100	0
751	982	2	300	0
752	984	6	300	0
753	986	2	100	0
754	990	6	100	0
755	991	2	100	0
756	991	5	300	0
757	992	8	300	0
758	992	4	200	0
759	993	8	100	0
760	994	5	100	0
761	994	2	200	0
762	998	6	300	0
763	998	2	100	0
764	1003	4	200	0
765	1006	6	300	0
766	1007	6	200	0
767	1008	5	200	0
768	1009	8	300	0
769	1009	8	300	0
770	1010	3	300	0
771	1010	1	300	0
772	1014	5	100	0
773	1014	8	200	0
774	1017	7	100	0
775	1017	7	200	0
776	1020	7	100	0
777	1023	6	100	0
778	1023	2	100	0
779	1024	9	200	0
780	1028	6	100	0
781	1028	9	300	0
782	1029	2	200	0
783	1029	9	300	0
784	1033	9	200	0
785	1034	6	300	0
786	1036	9	100	0
787	1042	2	300	0
788	1044	9	100	0
789	1045	6	300	0
790	1045	2	300	0
791	1048	2	100	0
792	1048	6	200	0
793	1049	7	300	0
794	1050	7	200	0
795	1050	6	200	0
796	1053	2	300	0
797	1053	2	300	0
798	1054	2	200	0
799	1054	7	200	0
800	1056	6	100	0
801	1057	2	100	0
802	1057	6	200	0
803	1059	6	200	0
804	1059	9	300	0
805	1061	6	300	0
806	1061	9	100	0.5
807	1062	9	100	0
808	1066	6	100	0
809	1068	1	300	0
810	1068	3	100	0.5
811	1072	6	300	0
812	1072	4	200	0
813	1074	6	300	0.5
814	1075	5	300	0
815	1077	6	200	0
816	1077	9	100	0
817	1078	2	300	0
818	1078	9	100	0
819	1080	2	200	0
820	1084	2	300	0
821	1084	6	100	0
822	1086	9	300	0
823	1087	9	100	0
824	1088	2	300	0
825	1088	9	100	0
826	1090	2	100	0
827	1091	9	200	0
828	1092	9	100	0
829	1092	2	200	0
830	1094	2	200	0
831	1095	9	100	0
832	1097	2	300	0
833	1097	6	200	0
834	1098	2	200	0
835	1099	7	100	0
836	1102	6	200	0
837	1102	7	300	0
838	1103	2	200	0
839	1105	7	200	0
840	1106	7	300	0
841	1106	6	200	0
842	1108	2	300	0
843	1108	9	300	0
844	1109	6	300	0
845	1111	9	100	0
846	1111	2	300	0.5
847	1114	2	300	0
848	1115	9	300	0
849	1116	2	300	0
850	1117	9	300	0
851	1119	9	300	0
852	1121	2	100	0
853	1121	2	300	0
854	1122	7	100	0
855	1123	6	300	0.5
856	1123	2	300	0
857	1125	2	200	0
858	1125	2	100	0
859	1127	2	200	0.5
860	1129	6	200	0
861	1129	6	300	0
862	1131	7	200	0
863	1135	6	200	0
864	1137	7	300	0.5
865	1139	2	100	0
866	1139	2	200	0
867	1140	6	300	0
868	1140	6	300	0
869	1141	6	300	0
870	1141	6	100	0
871	1142	2	100	0
872	1150	1	100	0
873	1151	1	200	0
874	1158	6	300	0
875	1159	6	200	0
876	1160	2	100	0
877	1163	9	300	0
878	1165	2	200	0
879	1168	2	100	0
880	1172	2	100	0
881	1173	4	300	0
882	1175	10	100	0
883	1177	9	200	0
884	1177	6	100	0
885	1180	2	300	0
886	1182	6	200	0
887	1184	6	300	0
888	1185	2	100	0
889	1188	2	200	0
890	1189	7	200	0
891	1190	6	100	0.5
892	1190	7	300	0
893	1191	2	100	0
894	1192	9	100	0
895	1194	6	200	0
896	1197	9	200	0
897	1197	10	200	0
898	1200	6	100	0
899	1200	2	100	0
900	1201	6	300	0
901	1203	2	300	0
902	1203	9	300	0
903	1204	6	200	0
904	1204	7	200	0
905	1206	7	300	0
906	1206	7	300	0
907	1207	2	200	0
908	1210	7	200	0
909	1211	9	200	0
910	1211	2	300	0
911	1220	1	100	0
912	1222	2	300	0
913	1222	5	100	0
914	1223	6	200	0
915	1223	3	200	0
916	1226	8	300	0
917	1226	5	200	0
918	1227	5	100	0
919	1228	8	300	0
920	1228	6	200	0
921	1230	4	300	0
922	1230	6	300	0
923	1231	3	100	0
924	1231	9	100	0
925	1233	2	100	0
926	1233	7	300	0
927	1234	6	100	0
928	1237	6	200	0
929	1239	7	100	0
930	1241	7	100	0.5
931	1241	2	200	0
932	1242	6	100	0
933	1245	9	200	0
934	1245	9	200	0
935	1246	9	300	0
936	1248	2	100	0
937	1248	6	200	0
938	1249	6	300	0
939	1249	2	300	0
940	1250	6	100	0
941	1250	6	200	0
942	1251	6	300	0
943	1251	9	100	0
944	1253	2	200	0
945	1253	2	300	0
946	1255	2	200	0
947	1256	2	200	0
948	1257	6	300	0
949	1257	7	100	0
950	1260	6	100	0
951	1260	2	100	0
952	1261	2	200	0
953	1263	2	300	0
954	1263	6	100	0
955	1264	2	100	0
956	1266	7	100	0
957	1266	2	300	0
958	1267	2	200	0
959	1269	2	300	0
960	1270	7	300	0
961	1270	2	200	0
962	1274	2	300	0
963	1275	2	300	0
964	1277	6	300	0
965	1277	2	300	0
966	1278	9	200	0
967	1278	9	200	0
968	1280	9	100	0
969	1280	6	300	0
970	1281	2	300	0
971	1281	9	200	0
972	1282	6	200	0
973	1282	9	200	0
974	1284	2	100	0
975	1288	5	100	0
976	1291	4	100	0
977	1292	4	200	0
978	1297	6	200	0
979	1301	9	100	0
980	1302	9	300	0
981	1302	9	200	0
982	1303	6	300	0
983	1303	9	100	0
984	1304	6	200	0
985	1305	7	100	0
986	1305	6	100	0
987	1308	2	200	0
988	1308	6	200	0
989	1309	2	200	0
990	1313	6	100	0
991	1313	7	200	0
992	1316	9	100	0
993	1317	9	200	0
994	1318	9	300	0
995	1318	6	300	0
996	1319	9	300	0
997	1319	2	300	0
998	1320	9	100	0
999	1321	2	100	0
1000	1322	6	300	0
1001	1322	6	100	0
1002	1326	2	300	0
1003	1326	7	300	0
1004	1329	1	300	0
1005	1329	3	300	0
1006	1332	2	100	0
1007	1332	6	200	0.5
1008	1334	3	300	0
1009	1334	3	100	0
1010	1335	4	200	0
1011	1340	10	100	0
1012	1344	4	300	0
1013	1345	6	200	0
1014	1346	5	300	0
1015	1346	5	300	0
1016	1347	9	200	0
1017	1348	6	100	0
1018	1348	6	200	0
1019	1349	5	200	0
1020	1349	4	300	0
1021	1350	10	300	0.5
1022	1350	10	100	0
1023	1352	4	300	0
1024	1352	5	200	0
1025	1353	9	100	0
1026	1354	6	100	0.5
1027	1354	2	100	0
1028	1355	2	300	0
1029	1356	2	200	0
1030	1356	2	200	0
1031	1357	5	300	0
1032	1362	9	300	0
1033	1363	9	100	0
1034	1365	6	300	0
1035	1365	6	300	0
1036	1368	2	100	0
1037	1374	1	200	0
1038	1374	5	300	0
1039	1378	5	200	0
1040	1378	2	100	0
1041	1379	5	100	0
1042	1380	2	200	0
1043	1382	5	300	0
1044	1383	9	100	0
1045	1384	2	200	0
1046	1385	9	300	0
1047	1385	9	300	0
1048	1386	9	100	0
1049	1387	2	300	0
1050	1388	6	200	0
1051	1388	2	200	0
1052	1390	6	300	0
1053	1393	9	300	0
1054	1394	2	100	0
1055	1394	2	100	0
1056	1396	2	100	0
1057	1396	2	300	0
1058	1399	2	200	0
1059	1401	2	300	0.5
1060	1401	2	100	0
1061	1403	8	300	0
1062	1403	1	100	0
1063	1404	9	200	0
1064	1405	4	100	0
1065	1405	6	100	0
1066	1406	4	100	0
1067	1406	9	200	0
1068	1407	3	200	0
1069	1407	6	300	0
1070	1408	6	100	0
1071	1408	2	200	0
1072	1409	3	100	0
1073	1410	9	200	0
1074	1411	3	100	0
1075	1413	6	100	0
1076	1415	8	200	0
1077	1415	3	200	0
1078	1416	5	300	0
1079	1416	5	200	0
1080	1418	3	200	0
1081	1422	2	300	0
1082	1422	3	100	0
1083	1429	6	100	0
1084	1429	6	100	0
1085	1432	9	300	0
1086	1432	2	300	0
1087	1434	9	200	0
1088	1435	6	200	0
1089	1443	2	200	0
1090	1446	2	200	0
1091	1446	2	200	0
1092	1447	9	300	0
1093	1449	6	200	0
1094	1449	9	100	0
1095	1452	2	100	0
1096	1452	6	100	0
1097	1456	9	100	0
1098	1456	9	200	0
1099	1459	6	200	0
1100	1459	6	100	0
1101	1462	2	300	0
1102	1463	2	300	0
1103	1463	1	100	0
1104	1465	6	200	0
1105	1465	9	200	0
1106	1466	2	200	0
1107	1467	6	200	0
1108	1467	10	100	0
1109	1468	2	200	0
1110	1469	10	100	0
1111	1469	6	200	0
1112	1470	5	300	0
1113	1470	10	100	0
1114	1472	5	200	0
1115	1475	9	200	0
1116	1475	10	200	0
1117	1479	4	200	0
1118	1479	9	100	0
1119	1485	6	100	0.5
1120	1487	7	200	0
1121	1488	2	100	0
1122	1488	6	300	0
1123	1490	7	300	0
1124	1491	6	200	0
1125	1491	6	300	0
1126	1499	5	300	0
1127	1499	5	200	0
1128	1502	1	100	0
1129	1503	8	100	0
1130	1504	8	100	0
1131	1504	1	200	0
1132	1506	1	200	0
1133	1506	9	200	0
1134	1508	1	200	0
1135	1508	1	200	0
1136	1509	5	300	0.5
1137	1509	1	200	0
1138	1511	9	100	0
1139	1511	6	100	0
1140	1513	2	300	0
1141	1515	1	300	0
1142	1518	5	200	0
1143	1518	3	100	0
1144	1520	10	200	0
1145	1520	2	300	0
1146	1524	6	100	0
1147	1525	3	200	0
1148	1527	3	300	0
1149	1527	2	200	0
1150	1529	6	300	0
1151	1533	7	100	0
1152	1535	6	100	0
1153	1535	2	300	0
1154	1538	6	300	0
1155	1538	6	100	0
1156	1539	7	100	0
1157	1539	2	300	0.5
1158	1543	3	300	0
1159	1543	3	200	0
1160	1544	1	100	0
1161	1544	1	100	0
1162	1545	2	300	0
1163	1545	1	200	0
1164	1546	4	200	0
1165	1546	6	200	0
1166	1547	5	100	0
1167	1547	8	200	0
1168	1548	1	200	0
1169	1548	5	200	0
1170	1551	9	100	0.5
1171	1552	9	100	0
1172	1554	6	300	0
1173	1554	1	100	0
1174	1559	6	100	0
1175	1559	6	300	0
1176	1561	6	100	0
1177	1562	6	200	0
1178	1562	7	200	0
1179	1564	7	200	0
1180	1564	2	100	0
1181	1566	2	100	0
1182	1566	2	100	0
1183	1567	6	300	0
1184	1567	7	100	0
1185	1570	2	100	0
1186	1571	6	100	0
1187	1571	2	300	0
1188	1574	6	300	0.5
1189	1574	4	300	0
1190	1576	4	300	0
1191	1576	2	100	0
1192	1580	5	200	0
1193	1584	5	300	0
1194	1584	5	100	0
1195	1585	4	300	0.5
1196	1586	6	100	0
1197	1586	2	100	0
1198	1587	1	100	0
1199	1593	5	100	0
1200	1596	2	100	0
1201	1597	9	100	0
1202	1599	3	300	0
1203	1602	9	100	0
1204	1602	4	200	0
1205	1604	1	100	0
1206	1604	2	100	0
1207	1605	5	100	0
1208	1605	5	200	0
1209	1608	9	200	0
1210	1608	8	300	0
1211	1610	3	200	0
1212	1611	5	200	0
1213	1612	9	100	0
1214	1613	9	200	0
1215	1615	6	100	0
1216	1621	6	200	0
1217	1621	2	200	0
1218	1622	6	300	0
1219	1624	2	200	0
1220	1624	6	200	0
1221	1625	6	100	0
1222	1625	9	300	0
1223	1627	6	200	0
1224	1629	9	200	0
1225	1632	9	200	0
1226	1633	6	100	0
1227	1633	2	300	0
1228	1634	9	200	0
1229	1635	6	100	0
1230	1636	2	200	0
1231	1636	6	300	0
1232	1638	6	300	0
1233	1638	6	300	0
1234	1639	6	200	0
1235	1640	6	100	0
1236	1640	9	100	0
1237	1642	2	200	0
1238	1642	9	200	0
1239	1645	9	100	0
1240	1645	6	100	0
1241	1648	6	100	0
1242	1648	9	200	0
1243	1649	2	300	0
1244	1651	1	300	0
1245	1652	8	200	0
1246	1652	3	100	0
1247	1654	5	300	0
1248	1654	3	300	0
1249	1655	8	200	0
1250	1655	1	200	0
1251	1656	6	300	0
1252	1659	2	200	0
1253	1660	6	300	0.5
1254	1660	2	200	0
1255	1661	1	300	0
1256	1661	3	300	0.5
1257	1662	1	100	0
1258	1665	5	300	0.5
1259	1665	1	300	0
1260	1666	5	200	0
1261	1666	1	300	0
1262	1668	9	200	0
1263	1668	2	200	0
1264	1669	10	200	0
1265	1669	6	300	0
1266	1672	10	200	0.5
1267	1672	6	300	0
1268	1673	5	200	0
1269	1673	5	300	0
1270	1676	4	300	0
1271	1676	1	100	0
1272	1678	4	200	0
1273	1678	9	100	0
1274	1679	9	200	0
1275	1681	3	300	0
1276	1681	3	200	0
1277	1683	9	100	0
1278	1683	9	300	0
1279	1686	7	300	0
1280	1687	6	100	0
1281	1689	6	300	0
1282	1689	9	100	0.5
1283	1692	6	100	0
1284	1693	9	300	0
1285	1696	6	300	0
1286	1698	2	200	0
1287	1701	2	300	0
1288	1702	10	200	0
1289	1702	5	100	0.5
1290	1703	6	200	0
1291	1705	9	100	0
1292	1705	10	200	0
1293	1706	6	100	0
1294	1706	6	200	0
1295	1707	6	300	0
1296	1711	9	300	0.5
1297	1714	6	100	0
1298	1715	6	100	0
1299	1715	9	200	0
1300	1716	6	200	0
1301	1716	9	100	0
1302	1717	2	100	0
1303	1718	6	200	0.5
1304	1718	9	100	0
1305	1719	3	300	0
1306	1719	8	300	0
1307	1725	8	300	0
1308	1725	5	200	0
1309	1727	6	100	0
1310	1728	5	300	0
1311	1728	4	200	0
1312	1730	2	200	0
1313	1730	5	200	0.5
1314	1731	2	100	0
1315	1733	9	100	0
1316	1733	2	200	0
1317	1735	3	300	0
1318	1735	5	100	0
1319	1738	9	200	0
1320	1738	8	300	0
1321	1739	8	200	0
1322	1742	1	200	0
1323	1745	2	300	0
1324	1745	4	200	0
1325	1746	9	300	0
1326	1746	4	200	0
1327	1748	8	200	0.5
1328	1749	4	100	0
1329	1749	6	100	0
1330	1751	1	300	0
1331	1753	9	200	0
1332	1756	4	100	0
1333	1757	5	200	0
1334	1758	2	200	0
1335	1760	2	300	0
1336	1760	6	200	0
1337	1761	6	200	0
1338	1761	4	300	0
1339	1764	9	200	0
1340	1764	2	200	0
1341	1766	2	200	0
1342	1767	5	200	0
1343	1768	5	100	0
1344	1768	10	200	0
1345	1769	2	100	0
1346	1769	10	200	0.5
1347	1771	5	100	0
1348	1771	4	200	0
1349	1773	10	300	0
1350	1773	9	100	0
1351	1774	6	100	0
1352	1774	2	200	0
1353	1775	6	200	0
1354	1775	2	100	0
1355	1776	6	300	0
1356	1777	9	100	0
1357	1781	9	300	0
1358	1781	2	200	0
1359	1785	6	300	0
1360	1789	9	100	0
1361	1789	9	100	0
1362	1790	2	300	0
1363	1790	9	200	0
1364	1791	5	100	0
1365	1793	6	300	0.5
1366	1793	9	200	0
1367	1794	5	200	0
1368	1799	10	100	0
1369	1800	2	300	0
1370	1800	6	200	0
1371	1805	10	200	0
1372	1805	10	200	0
1373	1806	5	200	0
1374	1806	5	200	0
1375	1808	5	100	0.5
1376	1808	6	100	0
1377	1812	2	100	0
1378	1816	6	100	0
1379	1817	9	200	0
1380	1818	2	300	0
1381	1819	9	200	0
1382	1820	6	300	0
1383	1826	2	200	0
1384	1827	6	200	0
1385	1827	6	200	0
1386	1828	9	200	0
1387	1828	6	200	0
1388	1830	6	300	0
1389	1830	6	100	0
1390	1833	1	200	0
1391	1835	6	300	0
1392	1836	6	100	0
1393	1836	5	100	0
1394	1837	8	100	0
1395	1840	5	300	0
1396	1840	9	100	0.5
1397	1841	4	300	0
1398	1844	8	100	0
1399	1844	2	200	0
1400	1845	3	200	0
1401	1845	3	200	0
1402	1847	3	100	0
1403	1849	8	100	0
1404	1850	2	200	0
1405	1851	5	300	0
1406	1851	9	200	0
1407	1852	1	300	0
1408	1852	4	200	0
1409	1854	2	100	0
1410	1854	3	300	0
1411	1855	5	100	0
1412	1858	4	200	0
1413	1865	9	300	0
1414	1865	9	100	0
1415	1869	6	100	0
1416	1871	6	100	0
1417	1871	9	200	0
1418	1873	6	300	0
1419	1873	2	300	0
1420	1874	9	200	0
1421	1876	6	200	0
1422	1877	6	100	0
1423	1877	6	300	0
1424	1878	2	300	0
1425	1879	9	300	0
1426	1879	9	200	0
1427	1884	9	200	0
1428	1887	10	300	0
1429	1887	10	100	0.5
1430	1889	4	100	0
1431	1889	9	100	0
1432	1893	6	100	0
1433	1893	9	300	0
1434	1895	9	100	0
1435	1900	9	200	0
1436	1900	2	100	0
1437	1901	9	200	0
1438	1901	6	300	0
1439	1904	6	300	0
1440	1904	9	100	0
1441	1905	2	100	0
1442	1907	6	100	0
1443	1907	2	100	0
1444	1908	9	300	0
1445	1911	6	300	0
1446	1912	9	100	0
1447	1912	2	300	0
1448	1913	2	200	0
1449	1913	9	200	0
1450	1915	6	200	0
1451	1915	6	100	0
1452	1917	9	100	0
1453	1918	1	100	0
1454	1918	2	100	0
1455	1922	2	300	0
1456	1923	5	200	0
1457	1924	6	300	0
1458	1924	6	100	0
1459	1925	2	100	0
1460	1928	2	200	0
1461	1929	2	200	0
1462	1929	2	100	0
1463	1931	9	200	0
1464	1931	6	300	0
1465	1935	2	200	0
1466	1936	2	100	0
1467	1936	7	300	0
1468	1937	7	300	0
1469	1938	6	300	0
1470	1938	2	200	0.5
1471	1941	2	200	0
1472	1943	10	200	0
1473	1945	9	100	0
1474	1949	6	200	0
1475	1949	2	300	0
1476	1950	3	500	0
1477	1950	5	200	0
\.


--
-- Name: visit_medicines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('visit_medicines_id_seq', 1477, true);


--
-- Data for Name: visits; Type: TABLE DATA; Schema: public; Owner: weikunliang
--

COPY visits (id, pet_id, date, weight, overnight_stay, total_charge) FROM stdin;
1	1	2012-03-09	5	\N	\N
2	1	2010-05-26	5	\N	\N
3	1	2010-05-20	2	\N	\N
4	1	2010-01-08	5	\N	\N
5	1	2011-12-26	6	\N	\N
6	1	2011-05-29	3	\N	\N
7	2	2010-04-07	29	\N	\N
8	2	2012-08-11	51	\N	\N
9	2	2008-04-19	48	\N	\N
10	2	2010-01-15	55	\N	\N
11	2	2009-10-21	28	\N	\N
12	2	2012-02-25	15	\N	\N
13	2	2010-10-29	16	\N	\N
14	2	2012-03-22	46	\N	\N
15	2	2011-03-07	55	\N	\N
16	2	2007-10-16	23	\N	\N
17	2	2009-11-13	19	\N	\N
18	3	2007-02-09	31	\N	\N
19	3	2012-08-19	35	\N	\N
20	3	2010-01-12	58	\N	\N
21	3	2007-06-06	17	\N	\N
22	4	2007-03-19	2	\N	\N
23	4	2011-01-10	7	\N	\N
24	4	2010-01-05	6	\N	\N
25	4	2010-06-18	6	\N	\N
26	4	2012-05-15	5	\N	\N
52	7	2008-10-13	7	\N	\N
27	5	2011-08-05	6	\N	\N
28	5	2011-01-25	11	\N	\N
29	5	2010-09-12	13	\N	\N
30	5	2011-11-02	13	\N	\N
31	5	2010-10-09	14	\N	\N
32	5	2009-11-08	13	\N	\N
33	5	2009-03-19	13	\N	\N
34	5	2010-03-21	8	\N	\N
35	5	2007-11-10	11	\N	\N
36	5	2011-05-11	14	\N	\N
37	5	2009-11-03	10	\N	\N
80	11	2011-08-03	6	\N	\N
130	16	2006-06-04	1	\N	\N
38	5	2008-07-31	6	\N	\N
39	6	2004-01-16	10	\N	\N
40	6	2009-09-28	12	\N	\N
41	6	2006-06-15	10	\N	\N
42	6	2010-09-07	8	\N	\N
43	6	2006-11-08	5	\N	\N
44	6	2007-08-23	9	\N	\N
45	6	2010-01-26	6	\N	\N
46	6	2005-05-08	9	\N	\N
47	6	2012-01-06	13	\N	\N
48	6	2006-04-10	5	\N	\N
49	7	2009-09-02	9	\N	\N
50	7	2011-07-02	14	\N	\N
51	7	2012-03-09	10	\N	\N
53	8	2005-04-21	14	\N	\N
54	8	2004-11-12	13	\N	\N
55	8	2009-02-27	6	\N	\N
56	8	2008-03-27	11	\N	\N
57	8	2003-11-19	13	\N	\N
58	9	2011-01-01	2	\N	\N
59	9	2011-09-06	5	\N	\N
60	9	2009-04-30	3	\N	\N
61	9	2007-12-05	3	\N	\N
62	10	2008-08-17	38	\N	\N
63	10	2004-08-08	14	\N	\N
64	10	2006-01-30	55	\N	\N
65	10	2009-05-28	24	\N	\N
66	10	2011-08-24	34	\N	\N
131	16	2006-12-29	2	\N	\N
145	18	2009-12-18	2	\N	\N
67	10	2011-02-25	19	\N	\N
68	10	2006-08-23	45	\N	\N
69	10	2010-01-13	13	\N	\N
70	10	2005-12-13	53	\N	\N
71	10	2007-04-29	15	\N	\N
72	10	2006-06-30	36	\N	\N
73	10	2006-01-15	34	\N	\N
74	10	2011-01-26	55	\N	\N
75	10	2005-04-29	49	\N	\N
76	10	2009-10-29	31	\N	\N
77	11	2009-10-12	3	\N	\N
78	11	2008-11-01	5	\N	\N
79	11	2010-03-08	1	\N	\N
81	11	2009-03-19	6	\N	\N
82	11	2008-09-16	1	\N	\N
83	12	2012-03-01	1	\N	\N
84	12	2011-11-30	6	\N	\N
85	12	2012-04-19	6	\N	\N
86	12	2012-07-05	2	\N	\N
87	12	2012-03-09	4	\N	\N
88	12	2012-02-15	2	\N	\N
89	13	2008-11-23	3	\N	\N
90	13	2009-08-26	7	\N	\N
91	13	2012-05-22	2	\N	\N
92	13	2010-01-13	6	\N	\N
93	13	2007-12-23	7	\N	\N
94	13	2011-11-21	7	\N	\N
95	13	2009-09-26	2	\N	\N
96	13	2011-08-11	3	\N	\N
97	13	2007-06-25	7	\N	\N
98	13	2009-12-16	2	\N	\N
99	13	2012-07-29	7	\N	\N
100	13	2011-09-12	2	\N	\N
101	13	2007-11-08	2	\N	\N
102	14	2005-12-19	5	\N	\N
103	14	2004-07-20	2	\N	\N
104	14	2010-11-24	3	\N	\N
116	15	2011-08-15	38	\N	\N
105	14	2007-03-09	6	\N	\N
106	14	2012-04-28	1	\N	\N
107	14	2007-02-27	5	\N	\N
108	14	2009-09-25	6	\N	\N
109	14	2004-04-09	3	\N	\N
110	14	2007-09-17	5	\N	\N
111	14	2003-08-24	4	\N	\N
112	14	2009-11-18	6	\N	\N
113	14	2003-11-17	2	\N	\N
114	14	2003-11-02	3	\N	\N
115	14	2006-12-03	2	\N	\N
117	15	2010-12-11	31	\N	\N
146	18	2008-06-12	3	\N	\N
118	15	2010-02-16	31	\N	\N
119	15	2011-03-24	36	\N	\N
120	15	2010-02-26	55	\N	\N
121	15	2011-04-24	34	\N	\N
122	15	2011-01-28	25	\N	\N
123	15	2007-01-11	21	\N	\N
124	15	2008-12-25	13	\N	\N
125	15	2008-09-21	48	\N	\N
126	16	2008-08-13	2	\N	\N
127	16	2012-11-02	1	\N	\N
128	16	2006-11-29	2	\N	\N
129	16	2009-08-12	2	\N	\N
147	18	2009-03-08	7	\N	\N
132	16	2009-05-29	1	\N	\N
133	16	2008-09-21	1	\N	\N
134	16	2007-01-12	2	\N	\N
135	16	2006-02-24	2	\N	\N
136	16	2008-11-29	1	\N	\N
137	17	2010-03-14	6	\N	\N
138	18	2007-10-22	5	\N	\N
139	18	2009-08-12	3	\N	\N
140	18	2011-11-04	2	\N	\N
141	18	2012-05-21	2	\N	\N
142	18	2011-12-23	7	\N	\N
143	18	2012-03-01	4	\N	\N
144	18	2011-12-10	5	\N	\N
188	25	2012-09-21	5	\N	\N
148	18	2011-04-16	5	\N	\N
149	18	2007-07-13	7	\N	\N
150	18	2007-10-29	5	\N	\N
151	19	2011-04-08	55	\N	\N
152	19	2010-07-10	23	\N	\N
153	19	2010-07-01	25	\N	\N
154	19	2010-10-27	48	\N	\N
155	19	2011-01-16	45	\N	\N
156	19	2010-11-07	42	\N	\N
157	19	2010-05-12	11	\N	\N
158	19	2012-01-14	48	\N	\N
159	19	2010-12-03	58	\N	\N
160	19	2010-06-02	57	\N	\N
161	19	2012-03-12	24	\N	\N
162	19	2012-06-11	13	\N	\N
163	19	2011-07-29	17	\N	\N
164	20	2011-12-18	20	\N	\N
165	21	2012-01-19	2	\N	\N
166	21	2012-06-26	2	\N	\N
167	21	2008-09-30	2	\N	\N
168	22	2006-10-30	24	\N	\N
169	22	2011-07-07	30	\N	\N
170	22	2009-03-13	39	\N	\N
171	22	2007-11-26	46	\N	\N
172	22	2012-06-14	21	\N	\N
173	22	2007-06-24	60	\N	\N
321	40	2012-05-15	3	\N	\N
174	22	2011-07-27	50	\N	\N
175	23	2010-08-22	11	\N	\N
176	24	2011-12-05	7	\N	\N
177	24	2012-10-01	2	\N	\N
178	24	2012-08-25	6	\N	\N
179	24	2012-08-05	5	\N	\N
180	24	2012-10-04	2	\N	\N
181	24	2012-01-06	2	\N	\N
182	25	2012-02-16	5	\N	\N
183	25	2012-04-03	3	\N	\N
184	25	2012-05-19	7	\N	\N
185	25	2011-12-21	4	\N	\N
186	25	2012-07-30	7	\N	\N
187	25	2012-04-08	4	\N	\N
189	25	2012-11-02	7	\N	\N
190	25	2012-09-10	6	\N	\N
191	26	2007-02-17	32	\N	\N
192	26	2007-03-08	48	\N	\N
193	26	2006-11-29	60	\N	\N
194	26	2007-06-07	37	\N	\N
195	26	2010-07-13	35	\N	\N
196	26	2008-11-18	13	\N	\N
197	26	2009-04-03	10	\N	\N
198	26	2009-08-29	40	\N	\N
199	26	2009-03-05	29	\N	\N
200	26	2011-06-27	39	\N	\N
201	27	2012-08-25	1	\N	\N
202	27	2010-11-08	1	\N	\N
350	44	2005-09-08	1	\N	\N
203	28	2005-11-03	5	\N	\N
204	28	2005-12-09	5	\N	\N
205	28	2010-11-28	2	\N	\N
206	28	2012-06-23	1	\N	\N
207	28	2007-01-15	1	\N	\N
208	28	2008-03-22	1	\N	\N
209	28	2008-12-13	6	\N	\N
210	28	2009-05-19	4	\N	\N
211	28	2008-07-30	3	\N	\N
212	28	2012-10-24	4	\N	\N
213	28	2004-02-21	2	\N	\N
351	44	2009-04-01	2	\N	\N
214	28	2004-09-12	5	\N	\N
215	29	2011-04-28	4	\N	\N
216	29	2011-08-14	2	\N	\N
217	29	2011-05-16	3	\N	\N
218	29	2011-06-24	2	\N	\N
219	29	2011-05-09	5	\N	\N
220	29	2012-09-27	4	\N	\N
221	29	2012-06-09	5	\N	\N
222	29	2012-07-13	6	\N	\N
223	29	2011-11-18	7	\N	\N
224	29	2011-06-27	3	\N	\N
225	29	2012-08-31	5	\N	\N
238	30	2011-12-15	2	\N	\N
226	30	2011-01-19	4	\N	\N
227	30	2009-10-20	3	\N	\N
228	30	2012-08-21	6	\N	\N
229	30	2008-10-12	5	\N	\N
230	30	2009-04-21	5	\N	\N
231	30	2010-07-16	3	\N	\N
232	30	2007-03-11	7	\N	\N
233	30	2007-04-28	6	\N	\N
234	30	2012-04-26	5	\N	\N
235	30	2012-04-24	5	\N	\N
236	30	2007-12-12	6	\N	\N
237	30	2007-12-25	6	\N	\N
253	32	2012-08-13	10	\N	\N
239	30	2011-05-21	7	\N	\N
240	30	2011-03-02	3	\N	\N
241	31	2011-04-19	4	\N	\N
242	31	2012-04-29	2	\N	\N
243	31	2011-08-12	3	\N	\N
244	31	2012-01-19	2	\N	\N
245	31	2011-04-04	4	\N	\N
246	31	2011-09-18	3	\N	\N
247	31	2011-11-03	5	\N	\N
248	31	2012-10-07	3	\N	\N
249	31	2011-08-14	6	\N	\N
250	31	2012-03-12	4	\N	\N
251	31	2012-09-07	5	\N	\N
252	31	2011-01-26	4	\N	\N
254	32	2010-04-17	7	\N	\N
255	33	2011-09-30	22	\N	\N
256	33	2012-03-30	15	\N	\N
257	33	2010-12-04	36	\N	\N
258	33	2009-08-09	20	\N	\N
259	33	2011-12-04	55	\N	\N
260	33	2009-07-08	47	\N	\N
261	33	2009-07-12	47	\N	\N
262	33	2012-05-13	28	\N	\N
263	33	2012-07-21	56	\N	\N
264	33	2010-05-11	55	\N	\N
265	33	2009-07-06	50	\N	\N
266	33	2010-02-03	47	\N	\N
267	33	2010-05-18	25	\N	\N
283	37	2012-02-01	3	\N	\N
479	57	2012-01-11	4	\N	\N
268	33	2010-01-27	50	\N	\N
269	34	2009-05-31	4	\N	\N
270	34	2011-07-10	2	\N	\N
271	34	2009-02-11	4	\N	\N
272	34	2009-01-31	6	\N	\N
273	34	2009-02-18	2	\N	\N
274	34	2007-10-17	6	\N	\N
275	34	2007-02-23	3	\N	\N
276	34	2012-01-01	2	\N	\N
277	35	2009-07-08	7	\N	\N
278	36	2009-07-29	2	\N	\N
279	36	2010-12-21	2	\N	\N
280	36	2010-08-10	1	\N	\N
281	36	2011-10-08	1	\N	\N
282	36	2011-12-08	1	\N	\N
284	37	2011-10-25	2	\N	\N
285	37	2012-04-20	6	\N	\N
286	37	2011-03-26	6	\N	\N
287	37	2010-12-23	4	\N	\N
288	37	2010-04-07	4	\N	\N
289	37	2012-02-11	2	\N	\N
290	37	2012-01-05	5	\N	\N
291	37	2010-09-30	5	\N	\N
292	38	2007-06-13	3	\N	\N
293	38	2007-09-06	7	\N	\N
294	38	2006-05-10	4	\N	\N
295	38	2009-01-12	6	\N	\N
296	38	2006-06-15	3	\N	\N
297	38	2008-05-28	7	\N	\N
298	38	2011-03-09	2	\N	\N
299	38	2004-04-24	4	\N	\N
300	38	2011-09-02	7	\N	\N
301	38	2008-04-13	5	\N	\N
302	38	2009-03-20	4	\N	\N
303	38	2004-10-04	5	\N	\N
304	38	2004-04-11	5	\N	\N
305	38	2011-08-05	4	\N	\N
306	39	2009-04-08	1	\N	\N
307	39	2009-10-20	2	\N	\N
308	39	2008-04-24	1	\N	\N
309	39	2012-02-22	2	\N	\N
310	39	2008-06-02	2	\N	\N
311	39	2011-12-10	2	\N	\N
312	39	2008-07-09	2	\N	\N
313	39	2012-06-09	2	\N	\N
314	39	2011-06-13	2	\N	\N
315	39	2012-08-09	2	\N	\N
316	39	2007-04-02	2	\N	\N
317	39	2007-04-21	1	\N	\N
318	39	2010-08-19	2	\N	\N
319	39	2009-06-12	2	\N	\N
320	40	2010-10-17	5	\N	\N
322	40	2008-08-07	5	\N	\N
323	41	2012-08-11	5	\N	\N
324	41	2009-09-25	5	\N	\N
325	42	2010-03-10	4	\N	\N
326	42	2005-09-25	4	\N	\N
327	42	2005-05-26	7	\N	\N
328	42	2009-07-30	6	\N	\N
329	42	2010-04-07	7	\N	\N
330	42	2007-03-26	4	\N	\N
331	42	2004-05-31	6	\N	\N
332	42	2007-04-23	2	\N	\N
333	42	2009-05-22	5	\N	\N
334	42	2010-01-24	3	\N	\N
1291	154	2011-12-03	15	\N	\N
335	42	2010-05-15	3	\N	\N
336	42	2011-06-11	6	\N	\N
337	42	2010-02-21	4	\N	\N
338	42	2007-11-22	4	\N	\N
339	42	2007-04-10	3	\N	\N
340	43	2008-06-21	60	\N	\N
341	43	2011-05-08	23	\N	\N
342	43	2006-07-22	57	\N	\N
343	43	2009-07-12	23	\N	\N
344	43	2005-08-23	57	\N	\N
345	43	2006-07-03	42	\N	\N
346	43	2005-04-10	39	\N	\N
347	43	2012-01-06	17	\N	\N
348	43	2009-01-20	16	\N	\N
349	43	2009-11-19	22	\N	\N
352	44	2004-11-27	2	\N	\N
353	44	2011-07-17	2	\N	\N
354	44	2011-03-09	1	\N	\N
355	44	2007-08-25	1	\N	\N
356	44	2007-11-22	2	\N	\N
357	44	2010-03-02	2	\N	\N
358	44	2006-05-21	1	\N	\N
359	44	2012-01-03	1	\N	\N
360	44	2007-11-08	1	\N	\N
361	44	2004-11-14	1	\N	\N
362	44	2010-05-05	1	\N	\N
363	44	2007-04-25	1	\N	\N
364	44	2010-01-21	2	\N	\N
365	45	2010-10-03	5	\N	\N
366	45	2005-12-19	5	\N	\N
1729	207	2010-11-22	12	\N	\N
367	45	2010-06-02	14	\N	\N
368	45	2010-04-24	7	\N	\N
369	45	2012-03-23	13	\N	\N
370	45	2005-11-17	13	\N	\N
371	45	2012-02-12	5	\N	\N
372	45	2006-06-17	11	\N	\N
373	45	2005-11-18	14	\N	\N
374	45	2012-04-24	14	\N	\N
375	45	2009-10-31	10	\N	\N
376	45	2009-07-23	10	\N	\N
377	46	2011-10-25	3	\N	\N
378	46	2004-08-29	7	\N	\N
379	46	2004-11-22	3	\N	\N
380	47	2011-05-09	2	\N	\N
381	47	2008-09-27	2	\N	\N
395	48	2010-10-30	6	\N	\N
382	47	2010-09-02	2	\N	\N
383	47	2008-05-14	1	\N	\N
384	47	2009-03-05	2	\N	\N
385	47	2009-12-03	2	\N	\N
386	47	2011-11-02	2	\N	\N
387	47	2012-02-04	1	\N	\N
388	47	2008-03-30	2	\N	\N
389	47	2012-11-02	2	\N	\N
390	47	2007-12-31	2	\N	\N
391	47	2008-11-26	1	\N	\N
392	47	2011-12-04	2	\N	\N
393	47	2009-08-12	2	\N	\N
394	47	2011-04-16	2	\N	\N
534	63	2011-11-08	48	\N	\N
396	48	2012-08-07	2	\N	\N
397	48	2009-02-18	5	\N	\N
398	48	2012-01-13	1	\N	\N
399	48	2009-04-20	3	\N	\N
400	48	2012-04-09	6	\N	\N
401	48	2011-09-29	3	\N	\N
402	48	2012-09-22	4	\N	\N
403	48	2012-06-03	3	\N	\N
404	48	2009-09-15	5	\N	\N
405	48	2009-09-04	4	\N	\N
406	48	2011-04-03	4	\N	\N
407	48	2010-03-20	6	\N	\N
408	48	2009-05-15	5	\N	\N
409	49	2009-05-11	6	\N	\N
410	49	2012-09-13	6	\N	\N
411	49	2009-07-16	3	\N	\N
412	49	2010-01-19	5	\N	\N
413	49	2010-03-27	7	\N	\N
414	49	2010-07-31	6	\N	\N
415	49	2009-12-06	7	\N	\N
416	49	2009-09-11	3	\N	\N
417	50	2010-07-07	2	\N	\N
418	50	2012-07-22	5	\N	\N
419	50	2009-12-09	5	\N	\N
420	50	2009-07-03	5	\N	\N
421	50	2011-07-31	3	\N	\N
449	54	2008-01-14	1	\N	\N
422	50	2012-07-17	2	\N	\N
423	50	2012-02-09	4	\N	\N
424	50	2009-10-28	4	\N	\N
425	50	2009-07-04	1	\N	\N
426	50	2011-10-14	3	\N	\N
427	50	2009-11-20	1	\N	\N
428	51	2004-04-12	1	\N	\N
429	51	2005-11-11	1	\N	\N
430	52	2012-03-06	2	\N	\N
431	52	2011-10-06	3	\N	\N
432	52	2012-01-10	5	\N	\N
433	52	2011-07-28	2	\N	\N
434	52	2012-10-24	1	\N	\N
464	56	2011-03-05	6	\N	\N
435	52	2012-09-15	3	\N	\N
436	53	2010-12-17	2	\N	\N
437	53	2012-05-23	4	\N	\N
438	53	2012-07-10	2	\N	\N
439	53	2010-12-28	4	\N	\N
440	53	2010-02-25	6	\N	\N
441	53	2010-11-02	5	\N	\N
442	53	2012-08-28	5	\N	\N
443	53	2011-08-29	2	\N	\N
444	53	2010-10-25	6	\N	\N
445	53	2010-02-22	2	\N	\N
446	53	2010-01-30	3	\N	\N
447	54	2008-05-27	2	\N	\N
448	54	2010-03-06	1	\N	\N
450	54	2007-07-25	3	\N	\N
451	54	2009-01-22	4	\N	\N
452	54	2007-03-16	6	\N	\N
453	55	2012-05-13	4	\N	\N
454	55	2012-03-16	2	\N	\N
455	55	2012-05-14	2	\N	\N
456	55	2012-08-12	3	\N	\N
457	55	2012-09-26	5	\N	\N
458	55	2012-08-29	5	\N	\N
459	55	2012-10-02	5	\N	\N
460	55	2012-03-18	1	\N	\N
461	55	2012-10-11	5	\N	\N
462	55	2012-03-30	4	\N	\N
463	55	2012-08-24	4	\N	\N
465	56	2010-10-16	14	\N	\N
466	56	2011-08-10	11	\N	\N
467	56	2012-11-08	13	\N	\N
468	56	2011-03-13	14	\N	\N
469	56	2010-07-02	8	\N	\N
470	56	2011-03-20	8	\N	\N
471	57	2009-06-07	2	\N	\N
472	57	2009-08-16	6	\N	\N
473	57	2010-09-18	5	\N	\N
474	57	2009-12-07	1	\N	\N
475	57	2009-11-08	5	\N	\N
476	57	2011-12-20	6	\N	\N
477	57	2010-10-26	3	\N	\N
478	57	2011-09-10	3	\N	\N
480	57	2010-08-09	2	\N	\N
481	57	2011-03-25	1	\N	\N
482	58	2006-03-17	43	\N	\N
483	58	2009-06-03	52	\N	\N
484	58	2009-12-25	41	\N	\N
485	58	2012-05-27	11	\N	\N
486	58	2010-02-25	27	\N	\N
487	58	2006-07-04	19	\N	\N
488	58	2006-10-05	30	\N	\N
489	58	2011-04-14	40	\N	\N
490	58	2010-11-14	36	\N	\N
491	58	2012-09-04	52	\N	\N
492	58	2005-12-11	50	\N	\N
569	68	2012-08-09	57	\N	\N
493	58	2012-06-12	15	\N	\N
494	59	2012-08-14	5	\N	\N
495	59	2012-02-07	7	\N	\N
496	59	2012-05-18	4	\N	\N
497	59	2011-11-14	4	\N	\N
498	59	2010-12-23	5	\N	\N
499	59	2012-07-27	2	\N	\N
500	59	2011-06-22	5	\N	\N
501	59	2011-08-21	2	\N	\N
502	59	2011-01-15	6	\N	\N
503	60	2009-12-11	2	\N	\N
504	60	2007-09-21	2	\N	\N
505	60	2011-01-12	1	\N	\N
506	60	2012-03-02	2	\N	\N
1179	143	2012-06-12	6	\N	\N
507	60	2010-01-12	2	\N	\N
508	60	2008-04-26	1	\N	\N
509	60	2011-02-07	1	\N	\N
510	61	2010-11-24	6	\N	\N
511	61	2011-01-28	4	\N	\N
512	61	2009-07-21	2	\N	\N
513	61	2010-12-30	5	\N	\N
514	61	2009-03-04	4	\N	\N
515	61	2009-03-05	6	\N	\N
516	61	2010-08-21	3	\N	\N
517	61	2008-04-19	2	\N	\N
518	61	2011-01-05	2	\N	\N
519	62	2008-02-29	7	\N	\N
520	62	2010-11-01	3	\N	\N
521	62	2012-07-05	4	\N	\N
570	68	2012-02-14	40	\N	\N
522	63	2011-12-20	28	\N	\N
523	63	2012-08-13	59	\N	\N
524	63	2011-12-12	50	\N	\N
525	63	2012-10-15	38	\N	\N
526	63	2012-07-07	48	\N	\N
527	63	2012-01-12	33	\N	\N
528	63	2012-05-14	53	\N	\N
529	63	2012-08-18	35	\N	\N
530	63	2012-03-07	44	\N	\N
531	63	2012-09-12	40	\N	\N
532	63	2012-03-10	20	\N	\N
533	63	2012-05-06	51	\N	\N
535	64	2012-06-30	11	\N	\N
536	64	2006-09-28	50	\N	\N
537	64	2008-05-17	25	\N	\N
538	64	2011-07-24	44	\N	\N
539	64	2012-05-08	58	\N	\N
540	64	2011-02-18	15	\N	\N
541	64	2010-01-10	18	\N	\N
542	64	2006-09-11	31	\N	\N
543	64	2012-08-24	22	\N	\N
544	64	2011-10-06	28	\N	\N
545	64	2011-03-24	20	\N	\N
546	64	2011-08-01	33	\N	\N
639	76	2012-10-23	5	\N	\N
547	64	2011-02-01	59	\N	\N
548	64	2011-03-22	10	\N	\N
549	64	2012-06-04	24	\N	\N
550	65	2011-02-14	1	\N	\N
551	66	2008-12-17	2	\N	\N
552	66	2009-09-06	7	\N	\N
553	66	2009-07-14	5	\N	\N
554	66	2006-10-14	4	\N	\N
555	66	2005-05-01	2	\N	\N
556	66	2012-02-27	4	\N	\N
557	66	2009-04-26	5	\N	\N
558	66	2007-03-30	7	\N	\N
1180	143	2011-12-15	3	\N	\N
559	66	2005-01-27	7	\N	\N
560	66	2008-06-28	5	\N	\N
561	66	2009-05-29	5	\N	\N
562	67	2011-03-30	11	\N	\N
563	67	2006-06-22	14	\N	\N
564	67	2011-06-03	5	\N	\N
565	67	2011-11-30	15	\N	\N
566	67	2010-06-08	8	\N	\N
567	68	2012-07-27	60	\N	\N
568	68	2012-03-13	42	\N	\N
571	68	2012-05-16	57	\N	\N
572	68	2012-06-03	58	\N	\N
573	68	2012-02-07	32	\N	\N
574	68	2012-03-26	24	\N	\N
575	69	2008-06-03	57	\N	\N
576	69	2006-06-29	45	\N	\N
577	69	2004-05-20	31	\N	\N
578	69	2010-09-01	10	\N	\N
579	69	2005-01-02	43	\N	\N
580	69	2008-05-09	21	\N	\N
581	69	2011-05-03	29	\N	\N
582	69	2005-02-09	52	\N	\N
583	69	2011-11-30	51	\N	\N
584	69	2009-06-08	60	\N	\N
585	69	2012-07-23	26	\N	\N
586	69	2011-10-10	25	\N	\N
587	70	2012-10-29	7	\N	\N
588	70	2007-08-26	5	\N	\N
589	70	2012-01-02	6	\N	\N
590	70	2007-03-14	4	\N	\N
591	70	2011-05-13	5	\N	\N
592	70	2009-03-02	5	\N	\N
593	70	2006-10-26	2	\N	\N
594	70	2011-09-29	2	\N	\N
595	70	2012-06-15	5	\N	\N
596	70	2007-04-17	5	\N	\N
597	70	2009-03-04	7	\N	\N
598	70	2011-10-16	6	\N	\N
599	71	2010-11-06	6	\N	\N
600	71	2009-12-22	2	\N	\N
601	71	2011-08-30	3	\N	\N
602	71	2010-04-22	5	\N	\N
603	71	2010-03-30	6	\N	\N
604	71	2012-07-15	3	\N	\N
605	71	2010-11-03	2	\N	\N
606	71	2008-12-24	6	\N	\N
607	72	2008-03-29	7	\N	\N
608	72	2006-06-23	15	\N	\N
609	73	2011-06-21	15	\N	\N
610	73	2012-07-04	12	\N	\N
611	73	2012-10-28	5	\N	\N
612	73	2011-11-08	14	\N	\N
613	73	2012-06-01	6	\N	\N
614	73	2012-10-24	8	\N	\N
615	73	2012-10-06	6	\N	\N
616	73	2011-09-24	14	\N	\N
617	73	2011-05-23	9	\N	\N
618	73	2011-08-02	9	\N	\N
619	73	2011-11-14	6	\N	\N
620	73	2012-02-04	14	\N	\N
621	73	2011-06-09	10	\N	\N
622	73	2012-11-02	7	\N	\N
623	73	2012-01-30	13	\N	\N
624	74	2004-03-11	2	\N	\N
678	82	2012-01-29	19	\N	\N
625	74	2012-07-19	1	\N	\N
626	74	2007-09-10	2	\N	\N
627	74	2006-02-01	1	\N	\N
628	75	2012-07-01	48	\N	\N
629	76	2012-05-05	3	\N	\N
630	76	2011-03-03	6	\N	\N
631	76	2009-07-13	6	\N	\N
632	76	2009-04-09	7	\N	\N
633	76	2008-12-31	3	\N	\N
634	76	2010-09-29	5	\N	\N
635	76	2010-05-15	5	\N	\N
636	76	2009-07-30	7	\N	\N
637	76	2008-08-30	7	\N	\N
638	76	2008-09-22	2	\N	\N
640	76	2008-12-10	5	\N	\N
641	77	2006-03-03	13	\N	\N
642	77	2010-09-29	22	\N	\N
643	77	2006-09-10	50	\N	\N
644	77	2011-07-13	15	\N	\N
645	77	2007-12-24	59	\N	\N
646	78	2011-06-18	4	\N	\N
647	78	2012-03-03	4	\N	\N
648	78	2012-09-09	6	\N	\N
649	78	2011-06-18	6	\N	\N
650	78	2012-05-15	2	\N	\N
651	79	2012-02-09	5	\N	\N
652	79	2012-10-07	1	\N	\N
653	79	2011-11-21	1	\N	\N
654	80	2004-06-23	4	\N	\N
655	80	2009-01-22	1	\N	\N
656	80	2009-04-07	5	\N	\N
657	80	2004-08-14	5	\N	\N
658	80	2008-10-30	6	\N	\N
659	80	2005-09-28	1	\N	\N
660	80	2005-05-03	1	\N	\N
661	80	2010-11-23	1	\N	\N
662	81	2012-08-21	6	\N	\N
663	81	2012-01-23	2	\N	\N
664	81	2011-08-09	2	\N	\N
1181	143	2011-06-20	4	\N	\N
665	81	2012-06-24	6	\N	\N
666	81	2012-04-12	3	\N	\N
667	81	2012-09-09	5	\N	\N
668	81	2011-11-02	1	\N	\N
669	81	2012-08-30	5	\N	\N
670	81	2011-04-07	6	\N	\N
671	81	2011-10-22	3	\N	\N
672	81	2012-06-28	1	\N	\N
673	81	2011-09-07	2	\N	\N
674	81	2012-11-09	4	\N	\N
675	82	2010-08-28	49	\N	\N
676	82	2011-06-14	52	\N	\N
677	82	2010-10-23	20	\N	\N
679	82	2010-11-26	27	\N	\N
680	82	2012-07-02	21	\N	\N
681	83	2010-01-26	2	\N	\N
682	83	2010-09-19	5	\N	\N
683	84	2010-04-22	12	\N	\N
684	84	2011-04-29	11	\N	\N
685	84	2010-08-19	19	\N	\N
686	84	2008-11-13	22	\N	\N
687	84	2008-08-15	59	\N	\N
688	84	2009-05-21	10	\N	\N
716	87	2012-03-04	13	\N	\N
689	84	2008-01-30	49	\N	\N
690	84	2008-03-15	27	\N	\N
691	84	2012-02-18	30	\N	\N
692	84	2009-09-16	46	\N	\N
693	84	2009-12-05	43	\N	\N
694	85	2010-05-12	5	\N	\N
695	85	2011-03-03	2	\N	\N
696	85	2010-09-14	7	\N	\N
697	85	2012-06-08	4	\N	\N
698	85	2010-01-21	4	\N	\N
699	85	2012-02-20	7	\N	\N
700	85	2011-08-05	6	\N	\N
701	85	2010-03-12	7	\N	\N
702	85	2012-06-14	7	\N	\N
703	85	2010-05-28	7	\N	\N
704	85	2012-06-12	3	\N	\N
705	85	2010-06-18	5	\N	\N
706	86	2007-08-10	3	\N	\N
707	86	2010-06-29	4	\N	\N
708	86	2010-05-24	6	\N	\N
709	86	2012-03-28	5	\N	\N
710	86	2009-07-11	7	\N	\N
711	86	2012-09-02	7	\N	\N
712	86	2010-07-21	7	\N	\N
713	86	2011-09-29	3	\N	\N
714	86	2008-11-24	2	\N	\N
715	86	2006-08-09	5	\N	\N
717	87	2011-08-08	5	\N	\N
718	87	2011-06-25	5	\N	\N
719	87	2011-05-14	8	\N	\N
720	87	2012-11-08	13	\N	\N
721	87	2012-10-29	15	\N	\N
722	87	2012-10-05	13	\N	\N
723	87	2011-01-22	8	\N	\N
724	87	2011-05-11	5	\N	\N
725	87	2012-01-29	13	\N	\N
726	87	2012-06-18	7	\N	\N
727	87	2012-02-24	13	\N	\N
728	88	2012-08-12	4	\N	\N
729	88	2012-09-08	6	\N	\N
730	88	2012-05-27	6	\N	\N
745	89	2006-08-20	1	\N	\N
731	88	2012-05-08	3	\N	\N
732	88	2012-09-17	1	\N	\N
733	88	2012-05-31	1	\N	\N
734	89	2009-06-07	2	\N	\N
735	89	2005-09-16	2	\N	\N
736	89	2007-03-03	1	\N	\N
737	89	2003-06-20	1	\N	\N
738	89	2003-07-03	1	\N	\N
739	89	2010-03-30	2	\N	\N
740	89	2012-05-23	1	\N	\N
741	89	2007-09-24	1	\N	\N
742	89	2006-07-15	2	\N	\N
743	89	2003-08-13	1	\N	\N
744	89	2011-08-02	1	\N	\N
746	90	2011-06-29	6	\N	\N
747	90	2011-10-16	4	\N	\N
748	90	2011-09-20	6	\N	\N
749	90	2011-08-16	1	\N	\N
750	90	2011-11-20	4	\N	\N
751	90	2012-02-10	3	\N	\N
752	90	2011-11-11	5	\N	\N
753	90	2011-06-17	6	\N	\N
754	91	2010-12-05	1	\N	\N
755	91	2007-02-03	3	\N	\N
756	91	2006-01-04	6	\N	\N
757	91	2007-01-15	1	\N	\N
758	91	2009-04-26	2	\N	\N
773	93	2011-07-18	4	\N	\N
759	91	2008-01-30	3	\N	\N
760	91	2012-03-11	3	\N	\N
761	91	2005-12-14	2	\N	\N
762	91	2012-07-21	3	\N	\N
763	91	2008-02-27	3	\N	\N
764	92	2010-07-07	12	\N	\N
765	93	2008-09-23	2	\N	\N
766	93	2007-02-08	7	\N	\N
767	93	2010-09-29	7	\N	\N
768	93	2010-07-01	2	\N	\N
769	93	2009-11-27	2	\N	\N
770	93	2011-08-15	4	\N	\N
771	93	2009-09-26	4	\N	\N
772	93	2008-09-23	5	\N	\N
774	93	2011-12-17	6	\N	\N
775	93	2008-11-06	7	\N	\N
776	93	2006-09-08	3	\N	\N
777	93	2012-03-07	2	\N	\N
778	93	2010-06-20	2	\N	\N
779	94	2012-10-21	4	\N	\N
780	94	2011-04-18	5	\N	\N
781	94	2011-06-16	6	\N	\N
782	95	2012-08-18	7	\N	\N
783	96	2012-08-24	2	\N	\N
784	96	2011-12-08	1	\N	\N
829	101	2012-04-14	6	\N	\N
785	96	2012-01-19	2	\N	\N
786	96	2012-03-16	2	\N	\N
787	96	2012-03-04	2	\N	\N
788	96	2012-05-17	2	\N	\N
789	96	2012-05-09	2	\N	\N
790	96	2012-08-21	2	\N	\N
791	96	2012-08-08	1	\N	\N
792	96	2012-04-24	1	\N	\N
793	96	2012-10-05	2	\N	\N
794	96	2012-04-24	1	\N	\N
795	97	2011-11-20	5	\N	\N
796	97	2010-04-29	6	\N	\N
797	97	2012-03-07	2	\N	\N
798	97	2011-07-29	7	\N	\N
799	97	2010-07-12	2	\N	\N
800	97	2012-08-05	3	\N	\N
801	97	2010-08-02	5	\N	\N
802	98	2011-08-05	1	\N	\N
803	98	2005-08-23	1	\N	\N
804	98	2011-11-16	2	\N	\N
805	98	2011-03-05	1	\N	\N
806	98	2006-10-27	2	\N	\N
807	98	2009-06-14	2	\N	\N
808	98	2011-05-04	1	\N	\N
809	98	2008-10-03	1	\N	\N
810	98	2012-06-05	1	\N	\N
811	98	2009-07-12	1	\N	\N
812	98	2005-09-24	2	\N	\N
813	99	2008-12-08	2	\N	\N
814	99	2005-12-22	1	\N	\N
815	99	2006-11-15	6	\N	\N
816	99	2007-05-27	6	\N	\N
817	99	2011-10-11	2	\N	\N
818	99	2003-04-01	4	\N	\N
819	99	2010-09-03	2	\N	\N
820	100	2008-05-02	11	\N	\N
821	100	2008-01-28	7	\N	\N
822	100	2010-09-02	11	\N	\N
823	100	2010-12-21	12	\N	\N
824	100	2007-08-14	15	\N	\N
825	101	2011-10-01	7	\N	\N
826	101	2010-05-12	7	\N	\N
827	101	2012-06-16	6	\N	\N
828	101	2012-08-28	2	\N	\N
830	101	2010-12-19	3	\N	\N
831	101	2012-03-22	4	\N	\N
832	101	2012-10-14	5	\N	\N
833	101	2012-08-24	4	\N	\N
834	101	2010-03-10	2	\N	\N
835	102	2004-06-19	2	\N	\N
836	102	2007-10-24	1	\N	\N
837	102	2007-09-18	1	\N	\N
838	102	2009-02-24	1	\N	\N
839	102	2009-12-21	1	\N	\N
840	103	2012-02-06	2	\N	\N
841	103	2011-09-20	1	\N	\N
842	103	2012-03-13	2	\N	\N
843	103	2011-12-27	1	\N	\N
1182	143	2011-07-21	1	\N	\N
844	103	2011-12-29	1	\N	\N
845	103	2012-09-13	2	\N	\N
846	103	2012-02-15	1	\N	\N
847	103	2011-07-25	2	\N	\N
848	103	2012-03-29	1	\N	\N
849	103	2012-02-05	1	\N	\N
850	104	2012-10-24	7	\N	\N
851	104	2012-05-10	7	\N	\N
852	104	2011-11-10	7	\N	\N
853	104	2011-04-17	2	\N	\N
854	104	2012-01-21	7	\N	\N
855	104	2012-10-11	7	\N	\N
918	114	2011-07-28	3	\N	\N
856	104	2011-11-21	4	\N	\N
857	105	2007-07-04	3	\N	\N
858	105	2007-07-19	6	\N	\N
859	105	2006-01-06	6	\N	\N
860	105	2006-11-15	5	\N	\N
861	105	2010-11-16	3	\N	\N
862	106	2011-04-13	10	\N	\N
863	106	2010-11-11	8	\N	\N
864	106	2011-08-02	10	\N	\N
865	106	2007-12-01	11	\N	\N
866	106	2008-12-07	7	\N	\N
867	107	2008-09-28	2	\N	\N
868	107	2011-07-30	1	\N	\N
869	107	2007-05-03	1	\N	\N
870	107	2011-12-31	6	\N	\N
871	107	2009-01-23	2	\N	\N
872	107	2011-07-23	2	\N	\N
873	107	2009-04-21	5	\N	\N
874	108	2011-08-18	3	\N	\N
875	108	2008-02-09	1	\N	\N
876	108	2011-06-07	6	\N	\N
877	108	2006-11-26	5	\N	\N
878	108	2012-06-17	1	\N	\N
892	109	2011-11-15	8	\N	\N
879	108	2010-11-01	3	\N	\N
880	108	2009-09-24	4	\N	\N
881	108	2012-01-22	6	\N	\N
882	108	2009-02-20	6	\N	\N
883	108	2012-04-24	5	\N	\N
884	108	2011-11-22	4	\N	\N
885	108	2012-01-26	2	\N	\N
886	109	2011-04-01	5	\N	\N
887	109	2011-03-09	9	\N	\N
888	109	2012-07-25	8	\N	\N
889	109	2012-07-08	9	\N	\N
890	109	2012-01-20	9	\N	\N
891	109	2011-05-13	12	\N	\N
893	109	2012-03-12	9	\N	\N
894	109	2012-08-06	8	\N	\N
895	110	2012-01-26	2	\N	\N
896	110	2008-06-26	1	\N	\N
897	111	2011-04-14	3	\N	\N
898	111	2009-05-08	7	\N	\N
899	111	2007-04-12	2	\N	\N
900	111	2008-06-30	6	\N	\N
901	111	2006-05-28	3	\N	\N
902	111	2009-02-16	3	\N	\N
903	111	2008-06-13	5	\N	\N
904	111	2006-12-02	5	\N	\N
905	111	2009-01-22	4	\N	\N
906	112	2004-02-07	1	\N	\N
1183	143	2012-06-02	1	\N	\N
907	113	2008-08-16	8	\N	\N
908	113	2008-08-24	8	\N	\N
909	113	2007-11-05	13	\N	\N
910	113	2011-02-19	13	\N	\N
911	113	2005-07-25	8	\N	\N
912	114	2011-10-23	3	\N	\N
913	114	2011-03-14	6	\N	\N
914	114	2011-12-29	3	\N	\N
915	114	2011-07-31	3	\N	\N
916	114	2011-07-01	4	\N	\N
917	114	2011-03-01	4	\N	\N
919	114	2011-05-06	6	\N	\N
920	114	2012-10-10	7	\N	\N
921	114	2012-01-02	3	\N	\N
922	114	2012-02-21	6	\N	\N
923	114	2011-05-25	2	\N	\N
924	114	2011-03-28	4	\N	\N
925	114	2012-06-03	4	\N	\N
926	114	2011-10-04	7	\N	\N
927	115	2010-11-04	11	\N	\N
928	115	2011-01-13	14	\N	\N
929	115	2010-08-13	11	\N	\N
930	115	2012-03-31	12	\N	\N
931	115	2011-12-08	5	\N	\N
1224	148	2008-11-22	29	\N	\N
932	115	2012-05-03	8	\N	\N
933	115	2012-10-03	14	\N	\N
934	115	2012-01-08	8	\N	\N
935	115	2012-05-21	11	\N	\N
936	115	2012-02-19	5	\N	\N
937	115	2010-10-28	14	\N	\N
938	116	2009-12-13	3	\N	\N
939	116	2009-04-23	5	\N	\N
940	116	2012-02-25	6	\N	\N
941	116	2008-08-21	7	\N	\N
942	116	2008-10-23	5	\N	\N
943	116	2008-08-15	7	\N	\N
944	116	2011-03-02	5	\N	\N
945	117	2010-05-04	11	\N	\N
1225	148	2010-03-21	51	\N	\N
946	117	2012-08-29	7	\N	\N
947	117	2009-04-19	12	\N	\N
948	117	2011-11-04	10	\N	\N
949	117	2011-06-12	15	\N	\N
950	117	2010-02-23	8	\N	\N
951	117	2009-12-27	8	\N	\N
952	117	2009-11-20	15	\N	\N
953	117	2011-09-14	8	\N	\N
954	117	2012-09-13	9	\N	\N
955	117	2010-09-10	14	\N	\N
956	117	2010-10-28	9	\N	\N
957	118	2004-06-06	7	\N	\N
958	118	2012-02-13	4	\N	\N
1374	167	2012-08-24	24	\N	\N
959	118	2009-03-06	6	\N	\N
960	119	2011-10-26	2	\N	\N
961	119	2009-02-01	7	\N	\N
962	119	2010-11-01	4	\N	\N
963	119	2012-08-24	2	\N	\N
964	119	2006-09-25	2	\N	\N
965	119	2006-10-30	6	\N	\N
966	119	2009-06-23	6	\N	\N
967	119	2007-12-11	5	\N	\N
968	119	2011-12-11	2	\N	\N
969	119	2009-08-17	2	\N	\N
970	119	2007-09-11	7	\N	\N
971	119	2008-04-13	7	\N	\N
1026	126	2012-03-18	5	\N	\N
972	119	2007-03-20	7	\N	\N
973	120	2010-04-29	3	\N	\N
974	120	2012-02-02	3	\N	\N
975	120	2012-06-11	3	\N	\N
976	120	2011-12-13	7	\N	\N
977	120	2012-07-02	4	\N	\N
978	120	2012-08-23	5	\N	\N
979	121	2012-11-02	6	\N	\N
980	121	2007-09-19	2	\N	\N
981	121	2010-05-01	5	\N	\N
982	121	2009-04-08	3	\N	\N
983	121	2012-01-03	5	\N	\N
984	121	2012-04-07	1	\N	\N
985	121	2012-07-14	4	\N	\N
986	121	2010-07-27	5	\N	\N
987	121	2011-06-23	1	\N	\N
988	121	2011-10-05	6	\N	\N
989	121	2006-06-18	3	\N	\N
990	121	2011-01-14	1	\N	\N
991	122	2011-06-21	53	\N	\N
992	122	2012-05-04	50	\N	\N
993	122	2011-12-25	18	\N	\N
994	122	2012-09-16	14	\N	\N
995	123	2006-02-13	6	\N	\N
996	123	2007-08-21	9	\N	\N
997	123	2010-09-18	15	\N	\N
998	123	2007-01-07	9	\N	\N
999	123	2012-04-25	12	\N	\N
1000	123	2009-03-20	9	\N	\N
1001	123	2010-11-05	11	\N	\N
1002	123	2009-06-01	12	\N	\N
1003	123	2009-10-19	15	\N	\N
1004	123	2007-07-06	7	\N	\N
1005	123	2009-05-14	15	\N	\N
1006	123	2012-06-23	5	\N	\N
1007	123	2011-12-05	10	\N	\N
1008	124	2009-08-17	60	\N	\N
1009	124	2011-10-20	40	\N	\N
1010	124	2011-12-18	53	\N	\N
1011	124	2009-12-15	41	\N	\N
1012	124	2011-03-20	21	\N	\N
1013	124	2011-02-14	24	\N	\N
1014	124	2012-05-25	37	\N	\N
1015	125	2012-08-14	2	\N	\N
1016	125	2012-06-10	1	\N	\N
1017	125	2012-05-12	1	\N	\N
1018	125	2012-09-02	1	\N	\N
1019	125	2012-03-18	2	\N	\N
1020	125	2012-05-12	1	\N	\N
1021	126	2011-10-17	4	\N	\N
1022	126	2012-06-25	6	\N	\N
1023	126	2011-04-23	5	\N	\N
1024	126	2011-04-05	2	\N	\N
1025	126	2012-05-25	7	\N	\N
1096	134	2011-09-19	6	\N	\N
1027	126	2011-05-01	5	\N	\N
1028	126	2011-10-26	6	\N	\N
1029	126	2012-07-05	7	\N	\N
1030	126	2011-06-26	2	\N	\N
1031	126	2011-12-22	7	\N	\N
1032	126	2011-03-16	5	\N	\N
1033	126	2012-05-11	6	\N	\N
1034	126	2011-11-07	3	\N	\N
1035	127	2004-03-24	5	\N	\N
1036	127	2005-09-05	5	\N	\N
1037	127	2008-10-05	2	\N	\N
1038	127	2010-02-17	5	\N	\N
1039	127	2005-04-20	5	\N	\N
1040	127	2011-02-20	4	\N	\N
1041	127	2008-02-26	3	\N	\N
1042	127	2004-02-19	3	\N	\N
1043	127	2009-01-11	2	\N	\N
1044	127	2006-04-06	5	\N	\N
1045	127	2007-08-05	3	\N	\N
1046	127	2007-07-15	1	\N	\N
1047	128	2007-12-09	1	\N	\N
1048	128	2009-10-13	2	\N	\N
1049	128	2003-10-13	1	\N	\N
1050	128	2008-03-26	1	\N	\N
1051	128	2004-07-05	2	\N	\N
1052	128	2007-02-08	2	\N	\N
1053	128	2010-10-05	2	\N	\N
1109	137	2009-06-01	6	\N	\N
1769	210	2005-07-25	14	\N	\N
1054	128	2012-02-19	2	\N	\N
1055	128	2006-11-08	2	\N	\N
1056	129	2009-09-01	2	\N	\N
1057	130	2003-05-01	1	\N	\N
1058	130	2008-06-13	2	\N	\N
1059	130	2010-10-02	6	\N	\N
1060	130	2008-06-16	6	\N	\N
1061	130	2010-12-13	4	\N	\N
1062	130	2007-11-06	3	\N	\N
1063	130	2006-05-21	2	\N	\N
1064	130	2006-10-12	4	\N	\N
1065	130	2008-09-24	4	\N	\N
1066	130	2005-03-15	5	\N	\N
1146	140	2010-11-16	45	\N	\N
1067	131	2012-06-01	40	\N	\N
1068	131	2012-06-30	18	\N	\N
1069	131	2012-11-06	47	\N	\N
1070	131	2012-08-18	47	\N	\N
1071	131	2012-06-16	57	\N	\N
1072	131	2012-04-24	47	\N	\N
1073	131	2012-10-26	49	\N	\N
1074	131	2012-05-24	55	\N	\N
1075	131	2012-07-23	47	\N	\N
1076	131	2012-09-24	28	\N	\N
1077	132	2005-09-26	4	\N	\N
1078	132	2005-09-30	4	\N	\N
1079	132	2008-06-24	5	\N	\N
1080	132	2005-03-09	5	\N	\N
1081	132	2011-11-03	3	\N	\N
1082	132	2012-04-05	3	\N	\N
1083	132	2010-10-23	4	\N	\N
1084	132	2011-05-30	1	\N	\N
1085	132	2009-08-12	2	\N	\N
1086	132	2006-03-02	3	\N	\N
1087	132	2012-09-25	6	\N	\N
1088	132	2005-11-22	4	\N	\N
1089	133	2012-06-02	4	\N	\N
1090	133	2012-04-19	5	\N	\N
1091	133	2011-07-21	3	\N	\N
1092	133	2010-06-15	1	\N	\N
1093	133	2009-10-26	4	\N	\N
1094	133	2008-10-19	1	\N	\N
1095	133	2010-01-14	2	\N	\N
1097	135	2012-09-08	2	\N	\N
1098	136	2004-11-30	1	\N	\N
1099	136	2007-07-03	2	\N	\N
1100	136	2008-04-20	1	\N	\N
1101	136	2012-09-19	1	\N	\N
1102	136	2006-01-26	1	\N	\N
1103	136	2006-07-13	2	\N	\N
1104	136	2009-02-23	2	\N	\N
1105	136	2005-09-11	2	\N	\N
1106	136	2010-09-23	1	\N	\N
1107	137	2008-11-22	5	\N	\N
1108	137	2011-09-21	4	\N	\N
1110	137	2007-02-18	6	\N	\N
1111	137	2005-09-01	1	\N	\N
1112	137	2006-09-07	1	\N	\N
1113	137	2010-02-03	3	\N	\N
1114	137	2011-01-23	4	\N	\N
1115	137	2003-11-26	3	\N	\N
1116	137	2003-07-21	3	\N	\N
1117	137	2007-07-01	6	\N	\N
1118	137	2006-08-29	3	\N	\N
1119	137	2012-04-18	3	\N	\N
1120	137	2012-09-09	6	\N	\N
1121	137	2012-05-12	6	\N	\N
1176	143	2012-08-26	3	\N	\N
1122	138	2012-08-13	1	\N	\N
1123	138	2012-05-23	1	\N	\N
1124	138	2012-10-12	1	\N	\N
1125	138	2012-08-29	2	\N	\N
1126	138	2012-04-17	2	\N	\N
1127	138	2012-10-06	2	\N	\N
1128	138	2012-10-04	2	\N	\N
1129	138	2012-03-24	1	\N	\N
1130	139	2007-06-18	2	\N	\N
1131	139	2012-04-21	1	\N	\N
1132	139	2008-11-12	1	\N	\N
1133	139	2008-01-22	2	\N	\N
1375	167	2010-12-11	48	\N	\N
1134	139	2010-02-06	2	\N	\N
1135	139	2006-04-16	1	\N	\N
1136	139	2010-07-15	1	\N	\N
1137	139	2011-05-26	2	\N	\N
1138	139	2007-11-01	2	\N	\N
1139	139	2009-03-21	2	\N	\N
1140	139	2012-03-07	1	\N	\N
1141	139	2012-03-16	1	\N	\N
1142	139	2011-06-14	2	\N	\N
1143	139	2006-02-11	1	\N	\N
1144	139	2009-06-12	2	\N	\N
1145	140	2011-06-29	47	\N	\N
1770	210	2010-12-04	13	\N	\N
1147	140	2010-04-16	23	\N	\N
1148	140	2009-12-11	55	\N	\N
1149	140	2012-07-05	40	\N	\N
1150	140	2012-04-29	60	\N	\N
1151	140	2011-11-09	11	\N	\N
1152	140	2012-08-25	50	\N	\N
1153	140	2008-11-07	11	\N	\N
1154	141	2011-12-04	6	\N	\N
1155	141	2005-12-31	2	\N	\N
1156	141	2012-09-01	1	\N	\N
1157	141	2009-05-26	4	\N	\N
1158	141	2008-07-10	4	\N	\N
1159	141	2011-09-23	1	\N	\N
1177	143	2012-10-31	4	\N	\N
1178	143	2012-04-10	1	\N	\N
1160	141	2007-02-05	1	\N	\N
1161	141	2008-05-06	4	\N	\N
1162	142	2012-03-29	11	\N	\N
1163	142	2012-08-19	11	\N	\N
1164	142	2012-04-15	13	\N	\N
1165	142	2011-04-21	13	\N	\N
1166	142	2010-06-24	13	\N	\N
1167	142	2012-10-12	12	\N	\N
1168	142	2012-09-21	13	\N	\N
1169	142	2010-11-28	14	\N	\N
1170	142	2012-10-06	5	\N	\N
1171	142	2011-06-15	7	\N	\N
1172	142	2011-12-03	5	\N	\N
1173	142	2011-12-16	8	\N	\N
1174	142	2010-08-05	8	\N	\N
1175	142	2010-08-11	13	\N	\N
1184	143	2012-05-16	3	\N	\N
1185	143	2011-08-07	6	\N	\N
1186	144	2011-10-31	1	\N	\N
1187	144	2012-08-21	1	\N	\N
1188	144	2011-11-08	1	\N	\N
1189	144	2012-10-31	1	\N	\N
1190	144	2012-05-21	1	\N	\N
1191	145	2012-02-24	5	\N	\N
1192	145	2012-05-21	14	\N	\N
1193	145	2012-11-09	13	\N	\N
1194	145	2012-04-24	5	\N	\N
1195	145	2012-03-07	10	\N	\N
1818	215	2007-03-31	3	\N	\N
1196	145	2012-03-13	7	\N	\N
1197	145	2012-08-17	14	\N	\N
1198	145	2012-05-09	14	\N	\N
1199	145	2012-07-29	13	\N	\N
1200	145	2012-02-18	13	\N	\N
1201	145	2012-04-03	5	\N	\N
1202	145	2012-05-10	5	\N	\N
1203	145	2012-05-14	13	\N	\N
1204	146	2012-07-31	2	\N	\N
1205	146	2010-10-01	2	\N	\N
1206	146	2010-03-17	1	\N	\N
1207	146	2012-02-25	1	\N	\N
1208	146	2012-08-12	1	\N	\N
1209	146	2011-04-12	1	\N	\N
1210	146	2012-10-27	1	\N	\N
1211	147	2010-11-24	5	\N	\N
1212	147	2012-08-23	2	\N	\N
1213	147	2011-10-29	2	\N	\N
1214	147	2012-03-03	6	\N	\N
1215	147	2011-09-13	7	\N	\N
1216	147	2011-05-27	4	\N	\N
1217	147	2011-02-19	6	\N	\N
1218	147	2012-05-19	7	\N	\N
1219	147	2011-11-15	6	\N	\N
1220	148	2007-03-31	24	\N	\N
1221	148	2012-11-09	41	\N	\N
1222	148	2008-10-04	51	\N	\N
1223	148	2007-10-13	32	\N	\N
1226	148	2009-08-24	19	\N	\N
1227	148	2010-05-20	16	\N	\N
1228	148	2011-04-09	59	\N	\N
1229	148	2011-11-17	37	\N	\N
1230	148	2010-09-25	24	\N	\N
1231	148	2012-06-18	41	\N	\N
1232	148	2012-04-19	55	\N	\N
1233	149	2004-01-08	1	\N	\N
1234	149	2012-10-26	1	\N	\N
1235	149	2006-06-24	2	\N	\N
1236	149	2005-07-17	1	\N	\N
1237	149	2005-05-29	2	\N	\N
1238	149	2008-12-30	2	\N	\N
1239	149	2004-10-15	1	\N	\N
1240	149	2006-07-19	1	\N	\N
1241	149	2007-09-21	2	\N	\N
1242	149	2006-07-22	1	\N	\N
1243	149	2003-03-07	2	\N	\N
1244	150	2012-06-12	2	\N	\N
1245	150	2012-06-03	1	\N	\N
1246	150	2012-10-19	3	\N	\N
1247	150	2012-07-28	5	\N	\N
1248	150	2012-07-01	1	\N	\N
1249	150	2012-03-15	4	\N	\N
1250	150	2012-06-20	5	\N	\N
1251	150	2012-03-29	6	\N	\N
1318	158	2009-01-18	7	\N	\N
1252	150	2012-08-24	2	\N	\N
1253	150	2012-09-12	3	\N	\N
1254	150	2012-08-18	4	\N	\N
1255	151	2011-09-28	2	\N	\N
1256	151	2012-03-21	2	\N	\N
1257	151	2012-10-21	1	\N	\N
1258	151	2012-02-15	2	\N	\N
1259	151	2012-04-15	2	\N	\N
1260	151	2012-07-21	1	\N	\N
1261	151	2012-03-28	2	\N	\N
1262	151	2011-11-08	2	\N	\N
1263	151	2012-09-23	2	\N	\N
1264	151	2012-01-10	2	\N	\N
1346	163	2011-09-16	10	\N	\N
1265	152	2008-07-25	2	\N	\N
1266	152	2011-12-22	2	\N	\N
1267	152	2009-05-02	2	\N	\N
1268	152	2010-05-01	1	\N	\N
1269	152	2010-04-24	1	\N	\N
1270	152	2010-12-06	2	\N	\N
1271	152	2010-04-21	1	\N	\N
1272	152	2007-10-28	1	\N	\N
1273	153	2011-12-10	7	\N	\N
1274	153	2012-10-16	7	\N	\N
1275	153	2011-08-26	4	\N	\N
1276	153	2012-11-03	3	\N	\N
1277	153	2012-08-18	6	\N	\N
1290	154	2011-11-28	10	\N	\N
1278	153	2012-04-23	5	\N	\N
1279	153	2012-04-16	5	\N	\N
1280	153	2012-01-23	5	\N	\N
1281	153	2012-03-11	5	\N	\N
1282	153	2012-04-08	2	\N	\N
1283	153	2012-08-10	4	\N	\N
1284	153	2012-10-02	3	\N	\N
1285	154	2011-11-22	13	\N	\N
1286	154	2012-01-24	11	\N	\N
1287	154	2012-08-26	5	\N	\N
1288	154	2012-05-21	9	\N	\N
1289	154	2012-05-22	11	\N	\N
1292	155	2012-02-29	12	\N	\N
1293	155	2007-08-05	7	\N	\N
1294	155	2012-10-09	13	\N	\N
1295	155	2011-08-17	15	\N	\N
1296	155	2009-02-03	6	\N	\N
1297	155	2011-09-29	5	\N	\N
1298	155	2007-02-10	14	\N	\N
1299	155	2011-01-02	11	\N	\N
1300	155	2011-12-25	7	\N	\N
1301	155	2007-09-15	13	\N	\N
1302	156	2010-08-18	2	\N	\N
1303	156	2011-12-07	5	\N	\N
1304	157	2012-04-17	1	\N	\N
1305	157	2012-03-29	1	\N	\N
1306	157	2005-09-26	1	\N	\N
1307	157	2012-09-27	2	\N	\N
1308	157	2011-02-12	1	\N	\N
1309	157	2006-05-09	1	\N	\N
1310	157	2010-05-07	1	\N	\N
1311	157	2006-03-01	2	\N	\N
1312	157	2011-02-02	2	\N	\N
1313	157	2010-07-25	1	\N	\N
1314	158	2012-03-23	6	\N	\N
1315	158	2009-06-30	4	\N	\N
1316	158	2009-08-15	7	\N	\N
1317	158	2012-01-15	2	\N	\N
1319	158	2009-04-10	3	\N	\N
1320	158	2011-05-05	4	\N	\N
1321	158	2011-10-22	3	\N	\N
1322	158	2011-05-07	5	\N	\N
1323	158	2009-07-30	3	\N	\N
1324	159	2009-05-14	1	\N	\N
1325	159	2010-11-26	2	\N	\N
1326	159	2009-12-14	1	\N	\N
1327	160	2011-07-10	2	\N	\N
1328	161	2012-11-06	11	\N	\N
1329	162	2010-02-19	57	\N	\N
1330	162	2012-05-05	35	\N	\N
1331	162	2008-08-01	48	\N	\N
1332	162	2011-04-26	32	\N	\N
1361	166	2012-08-16	4	\N	\N
1333	162	2010-04-12	54	\N	\N
1334	162	2011-11-17	39	\N	\N
1335	162	2009-10-22	59	\N	\N
1336	162	2010-05-10	36	\N	\N
1337	162	2009-06-20	42	\N	\N
1338	163	2011-04-14	8	\N	\N
1339	163	2012-01-28	13	\N	\N
1340	163	2011-05-20	6	\N	\N
1341	163	2012-01-05	5	\N	\N
1342	163	2011-07-13	12	\N	\N
1343	163	2012-01-07	14	\N	\N
1344	163	2011-09-16	10	\N	\N
1345	163	2012-03-01	14	\N	\N
1347	163	2011-06-27	10	\N	\N
1348	163	2011-04-19	5	\N	\N
1349	163	2012-08-02	6	\N	\N
1350	163	2012-01-15	9	\N	\N
1351	163	2011-07-06	15	\N	\N
1352	163	2012-05-17	10	\N	\N
1353	164	2010-08-28	5	\N	\N
1354	164	2008-03-27	5	\N	\N
1355	164	2010-05-27	3	\N	\N
1356	164	2010-12-13	7	\N	\N
1357	165	2009-04-08	59	\N	\N
1358	165	2012-04-21	49	\N	\N
1359	166	2012-04-10	6	\N	\N
1360	166	2012-07-04	6	\N	\N
1362	166	2012-10-25	3	\N	\N
1363	166	2012-10-30	6	\N	\N
1364	166	2012-08-13	7	\N	\N
1365	166	2012-05-12	6	\N	\N
1366	166	2012-03-22	5	\N	\N
1367	166	2012-07-08	6	\N	\N
1368	166	2012-06-04	7	\N	\N
1369	166	2012-06-20	3	\N	\N
1370	166	2012-06-14	3	\N	\N
1371	166	2012-05-02	4	\N	\N
1372	166	2012-05-06	5	\N	\N
1373	167	2007-01-28	11	\N	\N
1376	167	2012-05-12	37	\N	\N
1377	167	2007-09-09	13	\N	\N
1378	168	2011-03-25	58	\N	\N
1379	168	2011-04-14	52	\N	\N
1380	168	2010-04-03	22	\N	\N
1381	168	2010-10-31	39	\N	\N
1382	168	2011-06-17	48	\N	\N
1383	168	2010-12-29	40	\N	\N
1384	169	2007-07-31	2	\N	\N
1385	169	2012-03-04	1	\N	\N
1386	169	2007-05-30	4	\N	\N
1387	169	2007-05-26	2	\N	\N
1388	169	2011-07-19	2	\N	\N
1389	169	2005-08-17	3	\N	\N
1390	169	2011-04-11	5	\N	\N
1418	173	2012-06-29	21	\N	\N
1391	169	2006-08-26	4	\N	\N
1392	169	2008-02-19	3	\N	\N
1393	169	2006-02-13	5	\N	\N
1394	169	2009-01-04	6	\N	\N
1395	169	2005-11-26	6	\N	\N
1396	169	2008-03-02	6	\N	\N
1397	170	2009-04-01	2	\N	\N
1398	170	2008-07-05	1	\N	\N
1399	170	2009-07-06	2	\N	\N
1400	170	2011-03-18	1	\N	\N
1401	170	2011-01-01	2	\N	\N
1402	170	2012-06-15	1	\N	\N
1419	173	2012-03-29	33	\N	\N
1420	173	2012-06-17	55	\N	\N
1730	207	2012-03-16	48	\N	\N
1403	171	2012-07-14	23	\N	\N
1404	171	2012-08-02	19	\N	\N
1405	171	2010-07-28	20	\N	\N
1406	171	2010-09-04	51	\N	\N
1407	171	2012-08-02	36	\N	\N
1408	171	2010-12-03	16	\N	\N
1409	171	2012-05-11	54	\N	\N
1410	171	2011-12-08	33	\N	\N
1411	171	2011-01-13	30	\N	\N
1412	171	2012-06-14	16	\N	\N
1413	172	2006-12-11	31	\N	\N
1414	172	2008-02-19	23	\N	\N
1415	173	2012-08-30	50	\N	\N
1416	173	2012-02-15	21	\N	\N
1417	173	2011-12-25	34	\N	\N
1421	173	2012-09-21	48	\N	\N
1422	173	2012-05-21	49	\N	\N
1423	173	2012-07-06	17	\N	\N
1424	173	2011-11-10	51	\N	\N
1425	173	2011-10-25	12	\N	\N
1426	173	2011-11-21	52	\N	\N
1427	174	2012-02-16	5	\N	\N
1428	174	2009-10-17	5	\N	\N
1429	175	2010-07-03	6	\N	\N
1430	176	2011-02-18	13	\N	\N
1431	176	2012-06-20	14	\N	\N
1432	177	2009-10-17	3	\N	\N
1433	177	2011-05-17	5	\N	\N
1434	177	2010-11-25	6	\N	\N
1435	177	2010-06-23	2	\N	\N
1436	177	2009-01-03	2	\N	\N
1437	177	2011-10-06	4	\N	\N
1438	177	2012-01-10	6	\N	\N
1439	177	2011-10-17	1	\N	\N
1440	177	2009-04-01	5	\N	\N
1441	177	2008-12-20	1	\N	\N
1442	177	2011-06-16	6	\N	\N
1443	177	2009-11-23	2	\N	\N
1444	177	2010-10-10	6	\N	\N
1459	178	2011-09-24	6	\N	\N
1445	177	2010-08-18	5	\N	\N
1446	178	2011-09-26	2	\N	\N
1447	178	2012-02-12	2	\N	\N
1448	178	2011-06-19	3	\N	\N
1449	178	2008-10-03	7	\N	\N
1450	178	2008-08-02	7	\N	\N
1451	178	2006-11-17	6	\N	\N
1452	178	2010-12-05	7	\N	\N
1453	178	2010-02-12	6	\N	\N
1454	178	2007-10-24	2	\N	\N
1455	178	2011-03-23	3	\N	\N
1456	178	2012-10-19	2	\N	\N
1457	178	2012-06-16	2	\N	\N
1458	178	2012-08-01	2	\N	\N
1460	179	2008-10-04	7	\N	\N
1461	179	2006-10-23	6	\N	\N
1462	180	2007-08-22	11	\N	\N
1463	180	2008-12-19	14	\N	\N
1464	180	2006-07-04	34	\N	\N
1465	180	2006-09-12	39	\N	\N
1466	181	2007-12-09	10	\N	\N
1467	181	2009-07-24	12	\N	\N
1468	181	2009-04-12	7	\N	\N
1469	181	2008-06-28	9	\N	\N
1470	181	2005-02-22	6	\N	\N
1471	181	2010-09-23	10	\N	\N
1472	181	2007-02-06	7	\N	\N
1473	181	2007-02-25	5	\N	\N
1474	181	2006-10-25	6	\N	\N
1475	181	2008-10-06	7	\N	\N
1476	181	2006-05-19	11	\N	\N
1477	181	2006-10-17	5	\N	\N
1478	181	2004-10-13	12	\N	\N
1479	181	2009-08-11	12	\N	\N
1480	182	2009-07-16	2	\N	\N
1481	182	2008-02-13	1	\N	\N
1482	182	2007-02-01	2	\N	\N
1483	182	2011-02-02	2	\N	\N
1484	182	2011-11-30	2	\N	\N
1485	182	2005-08-01	1	\N	\N
1486	182	2007-02-21	2	\N	\N
1487	182	2011-06-30	2	\N	\N
1488	182	2007-12-03	1	\N	\N
1489	182	2007-04-03	2	\N	\N
1490	182	2005-02-11	2	\N	\N
1491	182	2012-11-01	2	\N	\N
1492	183	2010-10-12	53	\N	\N
1493	183	2011-10-12	46	\N	\N
1494	183	2009-11-13	54	\N	\N
1495	183	2008-12-02	24	\N	\N
1496	183	2010-01-07	25	\N	\N
1497	183	2011-02-07	15	\N	\N
1498	183	2009-05-11	58	\N	\N
1499	183	2012-06-11	14	\N	\N
1633	197	2012-10-23	5	\N	\N
1500	183	2009-03-26	33	\N	\N
1501	183	2011-04-20	38	\N	\N
1502	183	2010-10-08	16	\N	\N
1503	183	2011-06-19	36	\N	\N
1504	184	2006-04-15	32	\N	\N
1505	184	2007-11-14	27	\N	\N
1506	184	2011-05-12	10	\N	\N
1507	184	2009-04-06	29	\N	\N
1508	184	2005-10-17	28	\N	\N
1509	184	2006-02-14	23	\N	\N
1510	184	2005-09-03	44	\N	\N
1511	184	2005-02-09	18	\N	\N
1512	184	2010-02-26	23	\N	\N
1513	184	2007-01-28	56	\N	\N
1514	184	2006-12-10	48	\N	\N
1515	184	2006-11-14	11	\N	\N
1516	184	2011-11-30	41	\N	\N
1517	185	2004-07-24	55	\N	\N
1518	185	2010-12-29	13	\N	\N
1519	186	2012-04-14	15	\N	\N
1520	186	2011-01-11	6	\N	\N
1521	187	2007-03-21	14	\N	\N
1522	187	2012-02-02	11	\N	\N
1523	187	2010-01-19	11	\N	\N
1524	187	2004-01-14	51	\N	\N
1525	187	2008-11-29	25	\N	\N
1526	187	2004-12-16	53	\N	\N
1527	187	2005-03-11	35	\N	\N
1528	187	2006-06-25	52	\N	\N
1529	187	2004-01-27	57	\N	\N
1530	187	2009-05-09	13	\N	\N
1531	187	2004-05-13	29	\N	\N
1532	187	2012-08-16	47	\N	\N
1533	188	2011-10-25	2	\N	\N
1534	188	2012-04-14	1	\N	\N
1535	188	2012-08-11	1	\N	\N
1536	188	2012-04-07	2	\N	\N
1537	188	2011-11-08	2	\N	\N
1538	188	2012-07-21	1	\N	\N
1539	188	2011-02-19	2	\N	\N
1540	188	2012-02-23	1	\N	\N
1541	189	2011-09-14	36	\N	\N
1542	189	2012-04-14	18	\N	\N
1543	189	2012-05-03	36	\N	\N
1544	189	2011-05-30	18	\N	\N
1545	189	2012-05-19	51	\N	\N
1546	189	2011-10-14	60	\N	\N
1547	189	2011-09-10	47	\N	\N
1548	189	2012-05-29	40	\N	\N
1549	189	2012-11-06	38	\N	\N
1550	189	2011-12-27	33	\N	\N
1551	189	2012-09-24	55	\N	\N
1552	189	2011-06-01	23	\N	\N
1553	190	2009-11-11	29	\N	\N
1554	190	2010-07-31	44	\N	\N
1555	191	2007-09-24	2	\N	\N
1556	191	2011-09-01	2	\N	\N
1557	191	2010-02-04	2	\N	\N
1558	192	2011-11-08	2	\N	\N
1559	192	2011-05-14	2	\N	\N
1560	192	2007-07-31	2	\N	\N
1561	192	2009-04-01	2	\N	\N
1562	192	2011-11-10	1	\N	\N
1563	192	2009-07-10	1	\N	\N
1564	192	2011-07-02	1	\N	\N
1565	192	2011-01-20	1	\N	\N
1566	192	2010-03-04	1	\N	\N
1567	192	2008-07-26	2	\N	\N
1568	192	2011-09-26	2	\N	\N
1569	192	2010-11-23	2	\N	\N
1570	192	2010-09-02	2	\N	\N
1571	192	2010-10-27	1	\N	\N
1572	193	2009-10-28	6	\N	\N
1573	193	2011-09-29	15	\N	\N
1574	193	2007-08-14	10	\N	\N
1575	193	2003-11-29	7	\N	\N
1576	193	2004-11-05	14	\N	\N
1577	193	2004-12-18	12	\N	\N
1578	193	2007-04-15	12	\N	\N
1634	197	2012-06-23	4	\N	\N
1579	193	2005-12-28	11	\N	\N
1580	193	2012-04-12	5	\N	\N
1581	193	2006-12-15	12	\N	\N
1582	193	2005-03-26	10	\N	\N
1583	193	2011-12-15	5	\N	\N
1584	193	2010-08-07	8	\N	\N
1585	194	2010-04-01	33	\N	\N
1586	194	2008-07-06	60	\N	\N
1587	194	2008-09-30	18	\N	\N
1588	194	2010-09-06	17	\N	\N
1589	194	2009-09-21	18	\N	\N
1590	194	2012-03-19	36	\N	\N
1591	194	2012-09-02	32	\N	\N
1592	194	2012-11-03	24	\N	\N
1635	197	2011-02-17	2	\N	\N
1593	194	2009-05-10	60	\N	\N
1594	194	2010-02-27	24	\N	\N
1595	194	2008-12-19	23	\N	\N
1596	194	2008-06-25	27	\N	\N
1597	194	2008-07-11	48	\N	\N
1598	194	2011-01-19	37	\N	\N
1599	194	2009-07-22	28	\N	\N
1600	195	2011-10-22	57	\N	\N
1601	195	2012-08-31	46	\N	\N
1602	195	2012-10-10	32	\N	\N
1603	195	2011-12-07	20	\N	\N
1604	195	2011-02-10	12	\N	\N
1605	195	2011-03-26	46	\N	\N
1606	195	2010-09-20	16	\N	\N
1607	195	2011-12-26	39	\N	\N
1608	195	2011-11-04	25	\N	\N
1609	195	2010-10-16	18	\N	\N
1610	195	2011-08-08	37	\N	\N
1611	195	2012-03-10	43	\N	\N
1612	196	2011-06-14	3	\N	\N
1613	196	2012-04-05	1	\N	\N
1614	196	2012-08-06	1	\N	\N
1615	196	2010-10-27	6	\N	\N
1616	196	2011-08-09	4	\N	\N
1617	196	2011-08-22	1	\N	\N
1618	196	2012-11-02	3	\N	\N
1619	196	2011-06-26	6	\N	\N
1620	196	2011-12-15	4	\N	\N
1621	196	2012-11-01	2	\N	\N
1622	196	2012-10-31	3	\N	\N
1623	196	2012-02-12	2	\N	\N
1624	196	2011-05-07	6	\N	\N
1625	196	2012-10-20	2	\N	\N
1626	196	2011-06-03	4	\N	\N
1627	197	2012-06-28	7	\N	\N
1628	197	2010-11-07	2	\N	\N
1629	197	2012-08-17	2	\N	\N
1630	197	2010-11-30	2	\N	\N
1631	197	2010-11-09	6	\N	\N
1632	197	2011-01-01	3	\N	\N
1636	197	2008-12-21	7	\N	\N
1637	197	2010-05-02	3	\N	\N
1638	197	2011-10-23	7	\N	\N
1639	197	2009-07-21	7	\N	\N
1640	197	2009-09-20	3	\N	\N
1641	197	2010-02-09	7	\N	\N
1642	198	2011-04-08	36	\N	\N
1643	198	2012-06-30	42	\N	\N
1644	198	2009-04-03	22	\N	\N
1645	198	2012-07-01	22	\N	\N
1646	198	2011-04-04	26	\N	\N
1647	198	2007-04-26	16	\N	\N
1648	198	2008-08-11	32	\N	\N
1649	198	2007-02-16	51	\N	\N
1650	198	2007-08-01	45	\N	\N
1651	198	2010-09-28	15	\N	\N
1652	198	2007-01-23	19	\N	\N
1653	198	2010-11-03	15	\N	\N
1654	198	2007-05-09	53	\N	\N
1655	198	2012-03-09	55	\N	\N
1656	199	2006-12-07	25	\N	\N
1657	199	2011-01-09	22	\N	\N
1658	199	2005-02-08	22	\N	\N
1659	199	2009-05-27	24	\N	\N
1660	199	2011-12-29	58	\N	\N
1661	199	2004-02-05	41	\N	\N
1662	199	2004-05-09	44	\N	\N
1663	199	2003-10-25	31	\N	\N
1664	199	2003-07-22	60	\N	\N
1665	199	2011-06-29	39	\N	\N
1666	199	2009-04-18	36	\N	\N
1667	199	2005-01-13	30	\N	\N
1668	200	2012-04-21	6	\N	\N
1669	200	2011-04-07	6	\N	\N
1670	200	2011-04-17	10	\N	\N
1671	200	2011-12-30	12	\N	\N
1672	200	2011-04-14	7	\N	\N
1673	200	2012-02-09	11	\N	\N
1687	203	2009-05-01	7	\N	\N
1674	200	2011-07-05	15	\N	\N
1675	201	2011-06-07	53	\N	\N
1676	201	2011-11-23	53	\N	\N
1677	201	2011-07-09	28	\N	\N
1678	201	2011-10-14	44	\N	\N
1679	201	2011-09-25	37	\N	\N
1680	201	2011-10-02	40	\N	\N
1681	201	2012-04-07	37	\N	\N
1682	201	2011-08-20	14	\N	\N
1683	201	2011-09-03	37	\N	\N
1684	201	2012-04-27	17	\N	\N
1685	202	2006-02-15	1	\N	\N
1686	202	2005-05-05	1	\N	\N
1688	203	2011-09-28	3	\N	\N
1689	203	2011-12-25	4	\N	\N
1690	203	2008-10-11	3	\N	\N
1691	203	2008-03-30	3	\N	\N
1692	203	2010-01-19	6	\N	\N
1693	203	2012-05-11	3	\N	\N
1694	203	2003-10-19	3	\N	\N
1695	203	2008-08-05	3	\N	\N
1696	203	2007-04-23	2	\N	\N
1697	203	2004-10-05	2	\N	\N
1698	203	2003-05-18	4	\N	\N
1699	204	2010-04-20	15	\N	\N
1728	206	2012-05-02	32	\N	\N
1700	204	2010-03-19	9	\N	\N
1701	204	2010-05-01	7	\N	\N
1702	204	2012-07-20	10	\N	\N
1703	204	2012-06-05	15	\N	\N
1704	204	2010-04-16	6	\N	\N
1705	204	2011-05-21	7	\N	\N
1706	204	2012-01-10	12	\N	\N
1707	204	2010-03-23	8	\N	\N
1708	204	2011-03-05	7	\N	\N
1709	205	2006-09-18	4	\N	\N
1710	205	2011-08-08	4	\N	\N
1711	205	2007-09-23	6	\N	\N
1712	205	2008-01-30	5	\N	\N
1713	205	2011-02-28	4	\N	\N
1714	205	2012-02-06	7	\N	\N
1715	205	2010-07-18	5	\N	\N
1716	205	2010-01-15	5	\N	\N
1717	205	2007-04-28	6	\N	\N
1718	205	2009-05-10	3	\N	\N
1719	206	2011-06-12	15	\N	\N
1720	206	2011-05-06	42	\N	\N
1721	206	2012-04-22	42	\N	\N
1722	206	2010-11-09	41	\N	\N
1723	206	2010-10-13	37	\N	\N
1724	206	2012-03-14	45	\N	\N
1725	206	2011-04-01	55	\N	\N
1726	206	2012-02-07	23	\N	\N
1727	206	2011-03-06	56	\N	\N
1731	207	2011-03-14	31	\N	\N
1732	207	2012-02-14	30	\N	\N
1733	207	2012-04-12	55	\N	\N
1734	207	2011-09-05	20	\N	\N
1735	207	2012-01-07	48	\N	\N
1736	207	2011-06-16	56	\N	\N
1737	207	2011-04-19	14	\N	\N
1738	207	2012-07-21	18	\N	\N
1739	207	2012-05-27	45	\N	\N
1740	208	2010-05-23	38	\N	\N
1741	208	2011-05-24	54	\N	\N
1742	208	2009-01-11	22	\N	\N
1743	208	2009-05-06	40	\N	\N
1744	208	2010-02-25	14	\N	\N
1745	208	2009-05-11	15	\N	\N
1746	208	2011-12-23	30	\N	\N
1747	208	2012-11-07	34	\N	\N
1748	208	2011-08-08	26	\N	\N
1749	208	2012-09-24	16	\N	\N
1750	208	2012-08-12	24	\N	\N
1751	208	2011-10-22	28	\N	\N
1752	208	2011-07-12	47	\N	\N
1753	209	2011-12-28	8	\N	\N
1768	210	2005-06-01	6	\N	\N
1754	209	2012-07-18	9	\N	\N
1755	209	2011-10-13	10	\N	\N
1756	209	2012-04-05	8	\N	\N
1757	209	2012-07-08	8	\N	\N
1758	209	2012-06-18	7	\N	\N
1759	209	2011-12-17	6	\N	\N
1760	209	2012-07-07	6	\N	\N
1761	209	2012-01-04	15	\N	\N
1762	209	2011-11-01	7	\N	\N
1763	209	2012-07-26	14	\N	\N
1764	209	2011-10-27	11	\N	\N
1765	209	2012-01-06	13	\N	\N
1766	209	2012-04-17	8	\N	\N
1767	209	2011-12-03	11	\N	\N
1771	210	2010-09-21	11	\N	\N
1772	211	2009-06-06	6	\N	\N
1773	211	2011-07-08	11	\N	\N
1774	212	2010-11-09	4	\N	\N
1775	212	2010-07-22	3	\N	\N
1776	212	2012-06-19	3	\N	\N
1777	212	2012-05-25	3	\N	\N
1778	212	2010-09-26	6	\N	\N
1779	212	2011-12-04	3	\N	\N
1780	212	2010-03-11	2	\N	\N
1781	212	2011-01-05	3	\N	\N
1782	212	2011-06-19	6	\N	\N
1783	212	2010-06-10	4	\N	\N
1784	212	2010-05-09	6	\N	\N
1785	212	2010-06-16	6	\N	\N
1786	212	2012-04-12	3	\N	\N
1787	213	2011-05-28	15	\N	\N
1788	213	2010-05-09	15	\N	\N
1789	213	2007-06-28	11	\N	\N
1790	213	2009-07-14	10	\N	\N
1791	213	2006-07-11	11	\N	\N
1792	213	2008-01-08	14	\N	\N
1793	213	2012-10-23	11	\N	\N
1794	213	2008-01-22	9	\N	\N
1795	213	2006-07-02	11	\N	\N
1796	213	2005-05-17	11	\N	\N
1797	213	2005-10-16	8	\N	\N
1798	213	2006-11-03	6	\N	\N
1799	213	2012-02-16	6	\N	\N
1800	213	2007-03-26	5	\N	\N
1801	214	2011-11-19	15	\N	\N
1802	214	2010-04-07	10	\N	\N
1803	214	2010-11-28	13	\N	\N
1804	214	2010-09-25	8	\N	\N
1805	214	2011-02-05	15	\N	\N
1806	214	2010-11-24	12	\N	\N
1829	216	2009-11-26	5	\N	\N
1807	214	2010-10-14	11	\N	\N
1808	214	2009-01-22	13	\N	\N
1809	214	2009-07-21	11	\N	\N
1810	214	2007-08-06	8	\N	\N
1811	214	2008-05-21	12	\N	\N
1812	215	2008-09-26	3	\N	\N
1813	215	2010-04-09	7	\N	\N
1814	215	2012-10-11	4	\N	\N
1815	215	2006-09-30	4	\N	\N
1816	215	2005-12-19	2	\N	\N
1817	215	2011-12-12	2	\N	\N
1819	216	2007-09-28	7	\N	\N
1820	216	2009-04-25	6	\N	\N
1821	216	2012-08-21	3	\N	\N
1822	216	2006-12-15	4	\N	\N
1823	216	2009-04-12	2	\N	\N
1824	216	2010-06-21	6	\N	\N
1825	216	2012-01-15	6	\N	\N
1826	216	2008-05-18	4	\N	\N
1827	216	2007-11-02	7	\N	\N
1828	216	2011-06-10	7	\N	\N
1830	216	2011-01-10	7	\N	\N
1831	217	2012-03-17	49	\N	\N
1832	217	2011-12-24	30	\N	\N
1833	217	2012-08-31	60	\N	\N
1834	217	2010-01-13	23	\N	\N
1835	217	2009-10-09	37	\N	\N
1836	217	2012-02-26	25	\N	\N
1837	217	2012-03-09	52	\N	\N
1838	218	2007-08-07	8	\N	\N
1839	218	2011-03-17	10	\N	\N
1840	218	2010-09-09	5	\N	\N
1841	218	2009-02-22	11	\N	\N
1842	219	2011-03-13	57	\N	\N
1858	222	2011-06-21	21	\N	\N
1843	219	2011-02-21	13	\N	\N
1844	219	2011-05-17	35	\N	\N
1845	219	2011-07-07	28	\N	\N
1846	219	2012-02-11	32	\N	\N
1847	219	2012-07-01	31	\N	\N
1848	219	2011-12-30	19	\N	\N
1849	219	2012-05-01	39	\N	\N
1850	220	2009-03-18	57	\N	\N
1851	220	2009-02-06	28	\N	\N
1852	220	2009-08-07	24	\N	\N
1853	220	2012-05-04	43	\N	\N
1854	220	2011-07-25	52	\N	\N
1855	220	2008-11-25	11	\N	\N
1856	221	2006-12-26	1	\N	\N
1857	221	2010-11-25	1	\N	\N
1859	222	2011-04-28	35	\N	\N
1860	222	2010-08-14	12	\N	\N
1861	223	2009-12-13	5	\N	\N
1862	223	2009-12-26	4	\N	\N
1863	223	2010-07-22	3	\N	\N
1864	223	2010-11-03	4	\N	\N
1865	223	2012-09-27	3	\N	\N
1866	224	2011-02-22	3	\N	\N
1867	224	2012-09-21	6	\N	\N
1868	224	2011-08-26	5	\N	\N
1869	224	2012-06-01	6	\N	\N
1870	224	2012-11-08	6	\N	\N
1871	224	2011-08-06	6	\N	\N
1940	234	2009-06-10	1	\N	\N
1872	224	2012-03-17	2	\N	\N
1873	225	2010-02-08	1	\N	\N
1874	225	2012-05-22	1	\N	\N
1875	225	2010-03-31	6	\N	\N
1876	225	2011-07-17	2	\N	\N
1877	225	2012-08-12	5	\N	\N
1878	225	2009-08-03	1	\N	\N
1879	225	2011-11-02	2	\N	\N
1880	225	2012-01-11	4	\N	\N
1881	226	2011-11-07	13	\N	\N
1882	226	2012-01-11	14	\N	\N
1883	226	2012-08-19	12	\N	\N
1884	226	2011-01-22	15	\N	\N
1885	226	2012-01-26	5	\N	\N
1886	226	2012-10-03	7	\N	\N
1887	226	2012-06-19	8	\N	\N
1941	235	2011-07-01	2	\N	\N
1888	226	2012-03-22	15	\N	\N
1889	226	2011-02-12	5	\N	\N
1890	226	2011-05-19	11	\N	\N
1891	226	2011-12-04	13	\N	\N
1892	227	2012-04-29	3	\N	\N
1893	227	2012-07-20	3	\N	\N
1894	227	2012-08-30	4	\N	\N
1895	227	2012-09-02	1	\N	\N
1896	227	2012-09-23	2	\N	\N
1897	227	2011-01-02	3	\N	\N
1898	227	2012-09-18	5	\N	\N
1899	227	2011-06-01	2	\N	\N
1900	227	2010-08-11	4	\N	\N
1901	227	2012-04-05	5	\N	\N
1902	227	2010-09-02	3	\N	\N
1903	228	2012-09-16	3	\N	\N
1904	228	2012-06-28	1	\N	\N
1905	229	2011-07-31	4	\N	\N
1906	229	2012-01-28	2	\N	\N
1907	229	2011-12-07	3	\N	\N
1908	229	2012-02-26	3	\N	\N
1909	229	2011-10-06	7	\N	\N
1910	229	2012-10-02	6	\N	\N
1911	229	2011-08-16	7	\N	\N
1912	230	2009-10-09	5	\N	\N
1913	230	2012-10-07	7	\N	\N
1914	230	2011-01-08	3	\N	\N
1915	230	2009-06-08	7	\N	\N
1916	231	2008-07-18	27	\N	\N
1917	231	2009-04-23	27	\N	\N
1918	231	2012-04-29	50	\N	\N
1919	231	2006-05-31	58	\N	\N
1920	231	2009-03-16	32	\N	\N
1921	231	2009-04-15	14	\N	\N
1922	231	2012-05-31	33	\N	\N
1923	231	2009-09-15	10	\N	\N
1924	232	2009-10-30	8	\N	\N
1925	232	2007-09-25	13	\N	\N
1926	232	2008-11-19	13	\N	\N
1927	233	2006-08-06	3	\N	\N
1928	233	2006-04-14	1	\N	\N
1929	233	2007-10-07	1	\N	\N
1930	233	2009-02-02	1	\N	\N
1931	233	2005-01-28	6	\N	\N
1932	234	2010-09-27	2	\N	\N
1933	234	2009-10-12	2	\N	\N
1934	234	2011-07-24	2	\N	\N
1935	234	2010-03-04	1	\N	\N
1936	234	2011-04-08	1	\N	\N
1937	234	2012-06-29	1	\N	\N
1938	234	2010-11-08	1	\N	\N
1939	234	2008-10-07	2	\N	\N
1942	236	2012-04-08	14	\N	\N
1943	236	2012-01-09	5	\N	\N
1944	236	2009-06-08	5	\N	\N
1945	236	2010-02-25	7	\N	\N
1946	236	2012-03-02	13	\N	\N
1947	236	2011-01-25	12	\N	\N
1948	236	2012-06-21	15	\N	\N
1949	237	2009-08-22	3	\N	\N
1950	173	2014-12-08	39	f	36700
\.


--
-- Name: visits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: weikunliang
--

SELECT pg_catalog.setval('visits_id_seq', 1950, true);


--
-- Name: animal_medicines_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY animal_medicines
    ADD CONSTRAINT animal_medicines_pkey PRIMARY KEY (id);


--
-- Name: animals_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY animals
    ADD CONSTRAINT animals_pkey PRIMARY KEY (id);


--
-- Name: medicine_costs_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY medicine_costs
    ADD CONSTRAINT medicine_costs_pkey PRIMARY KEY (id);


--
-- Name: medicines_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY medicines
    ADD CONSTRAINT medicines_pkey PRIMARY KEY (id);


--
-- Name: notes_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: owners_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY owners
    ADD CONSTRAINT owners_pkey PRIMARY KEY (id);


--
-- Name: pets_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY pets
    ADD CONSTRAINT pets_pkey PRIMARY KEY (id);


--
-- Name: procedure_costs_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY procedure_costs
    ADD CONSTRAINT procedure_costs_pkey PRIMARY KEY (id);


--
-- Name: procedures_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY procedures
    ADD CONSTRAINT procedures_pkey PRIMARY KEY (id);


--
-- Name: treatments_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY treatments
    ADD CONSTRAINT treatments_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users_username_key; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: visit_medicines_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY visit_medicines
    ADD CONSTRAINT visit_medicines_pkey PRIMARY KEY (id);


--
-- Name: visits_pkey; Type: CONSTRAINT; Schema: public; Owner: weikunliang; Tablespace: 
--

ALTER TABLE ONLY visits
    ADD CONSTRAINT visits_pkey PRIMARY KEY (id);


--
-- Name: animalmedicines_animals_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX animalmedicines_animals_idx ON animal_medicines USING btree (animal_id);


--
-- Name: animalmedicines_medicines_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX animalmedicines_medicines_idx ON animal_medicines USING btree (medicine_id);


--
-- Name: medicinecosts_medicine_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX medicinecosts_medicine_idx ON medicine_costs USING btree (medicine_id);


--
-- Name: medicines_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX medicines_idx ON medicines USING gin (to_tsvector('english'::regconfig, description));


--
-- Name: notes_users_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX notes_users_idx ON notes USING btree (user_id);


--
-- Name: pets_animals_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX pets_animals_idx ON pets USING btree (animal_id);


--
-- Name: pets_owners_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX pets_owners_idx ON pets USING btree (owner_id);


--
-- Name: procedurecosts_procedure_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX procedurecosts_procedure_idx ON procedure_costs USING btree (procedure_id);


--
-- Name: treatments_procedures_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX treatments_procedures_idx ON treatments USING btree (procedure_id);


--
-- Name: treatments_visits_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX treatments_visits_idx ON treatments USING btree (visit_id);


--
-- Name: users_username_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX users_username_idx ON users USING btree (username);


--
-- Name: visitmedicines_medicines_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX visitmedicines_medicines_idx ON visit_medicines USING btree (medicine_id);


--
-- Name: visitmedicines_visits_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX visitmedicines_visits_idx ON visit_medicines USING btree (visit_id);


--
-- Name: visits_pets_idx; Type: INDEX; Schema: public; Owner: weikunliang; Tablespace: 
--

CREATE INDEX visits_pets_idx ON visits USING btree (pet_id);


--
-- Name: set_end_date_for_previous_medicine_cost; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER set_end_date_for_previous_medicine_cost BEFORE INSERT ON medicine_costs FOR EACH ROW EXECUTE PROCEDURE set_end_date_for_medicine_costs();


--
-- Name: set_end_date_for_previous_procedure_cost; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER set_end_date_for_previous_procedure_cost BEFORE INSERT ON procedure_costs FOR EACH ROW EXECUTE PROCEDURE set_end_date_for_procedure_cost();


--
-- Name: update_medicine_stock_amount; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER update_medicine_stock_amount AFTER INSERT OR UPDATE ON visit_medicines FOR EACH STATEMENT EXECUTE PROCEDURE decrease_stock_amount_after_dosage();


--
-- Name: update_overnight_stay_flag; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER update_overnight_stay_flag AFTER INSERT ON treatments FOR EACH STATEMENT EXECUTE PROCEDURE calculate_overnight_stay();


--
-- Name: update_total_costs_for_medicines_changes; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER update_total_costs_for_medicines_changes AFTER INSERT OR UPDATE ON visit_medicines FOR EACH ROW EXECUTE PROCEDURE calculate_total_costs();


--
-- Name: update_total_costs_for_treatments_changes; Type: TRIGGER; Schema: public; Owner: weikunliang
--

CREATE TRIGGER update_total_costs_for_treatments_changes AFTER INSERT OR UPDATE ON treatments FOR EACH ROW EXECUTE PROCEDURE calculate_total_costs();


--
-- Name: animal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY pets
    ADD CONSTRAINT animal_fkey FOREIGN KEY (animal_id) REFERENCES animals(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: animal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY animal_medicines
    ADD CONSTRAINT animal_fkey FOREIGN KEY (animal_id) REFERENCES animals(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: medicine_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY animal_medicines
    ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: medicine_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY visit_medicines
    ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: medicine_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY medicine_costs
    ADD CONSTRAINT medicine_fkey FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: owner_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY pets
    ADD CONSTRAINT owner_fkey FOREIGN KEY (owner_id) REFERENCES owners(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: pet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY visits
    ADD CONSTRAINT pet_fkey FOREIGN KEY (pet_id) REFERENCES pets(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: procedure_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY treatments
    ADD CONSTRAINT procedure_fkey FOREIGN KEY (procedure_id) REFERENCES procedures(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: procedure_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY procedure_costs
    ADD CONSTRAINT procedure_fkey FOREIGN KEY (procedure_id) REFERENCES procedures(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: visit_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY visit_medicines
    ADD CONSTRAINT visit_fkey FOREIGN KEY (visit_id) REFERENCES visits(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: visit_fkey; Type: FK CONSTRAINT; Schema: public; Owner: weikunliang
--

ALTER TABLE ONLY treatments
    ADD CONSTRAINT visit_fkey FOREIGN KEY (visit_id) REFERENCES visits(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: public; Type: ACL; Schema: -; Owner: weikunliang
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM weikunliang;
GRANT ALL ON SCHEMA public TO weikunliang;
GRANT ALL ON SCHEMA public TO pats;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: treatments; Type: ACL; Schema: public; Owner: weikunliang
--

REVOKE ALL ON TABLE treatments FROM PUBLIC;
REVOKE ALL ON TABLE treatments FROM weikunliang;
GRANT ALL ON TABLE treatments TO weikunliang;


--
-- Name: users; Type: ACL; Schema: public; Owner: weikunliang
--

REVOKE ALL ON TABLE users FROM PUBLIC;
REVOKE ALL ON TABLE users FROM weikunliang;
GRANT ALL ON TABLE users TO weikunliang;
GRANT SELECT ON TABLE users TO pats;


--
-- Name: visit_medicines; Type: ACL; Schema: public; Owner: weikunliang
--

REVOKE ALL ON TABLE visit_medicines FROM PUBLIC;
REVOKE ALL ON TABLE visit_medicines FROM weikunliang;
GRANT ALL ON TABLE visit_medicines TO weikunliang;


--
-- PostgreSQL database dump complete
--

