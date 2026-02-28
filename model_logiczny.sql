DROP TABLE IF EXISTS Zaplanowany_posiłek;
DROP TABLE IF EXISTS Składniki_przepisów;
DROP TABLE IF EXISTS Lista_zakupów;
DROP TABLE IF EXISTS Spiżarnia;
DROP TABLE IF EXISTS Przepisy;
DROP TABLE IF EXISTS Produkty;
DROP TABLE IF EXISTS Typy_dania;
DROP TABLE IF EXISTS Jednostki;


CREATE TABLE Jednostki(
    id_jednostki INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nazwa VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE Typy_dania(
    nazwa VARCHAR(30) PRIMARY KEY
);

CREATE TABLE Produkty(
    id_produktu INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nazwa VARCHAR(40) NOT NULL UNIQUE,
    kcal_na_ilość_ref NUMERIC(10,2),
    ilość_ref NUMERIC(5),
    id_jednostki INT NOT NULL REFERENCES Jednostki(id_jednostki),
    CONSTRAINT nieujemne_kcal 
        CHECK (kcal_na_ilość_ref>=0),
    CONSTRAINT dodatnia_ilość_ref 
        CHECK (ilość_ref>0)
);

CREATE TABLE Przepisy(
    id_przepisu INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nazwa VARCHAR(50) NOT NULL UNIQUE,
    opis TEXT,
    czas_przygotowania NUMERIC(4) NOT NULL,
    liczba_porcji NUMERIC(2) NOT NULL,
    typ_dania VARCHAR(30) NOT NULL REFERENCES Typy_dania(nazwa),
    kcal_na_osobę NUMERIC(4),
    czy_liczyć_kcal BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT dodatni_czas_przygotowania 
        CHECK (czas_przygotowania>0),
    CONSTRAINT dodatnia_liczba_porcji 
        CHECK (liczba_porcji>0),
    CONSTRAINT dodatni_kcal_na_osobę 
        CHECK (kcal_na_osobę>0)
);

CREATE TABLE Spiżarnia(
    id_produktu INT PRIMARY KEY,
    pozostała_ilość NUMERIC(10,2) NOT NULL,
    priorytet BOOLEAN NOT NULL DEFAULT FALSE,
    rezerwowana_ilość NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_spiżarnia 
        FOREIGN KEY (id_produktu) 
        REFERENCES Produkty(id_produktu),
    CONSTRAINT nieujemna_pozostała_ilość 
        CHECK (pozostała_ilość>=0)
);

CREATE TABLE Lista_zakupów(
    id_zakupu INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_produktu INT NOT NULL REFERENCES Produkty(id_produktu),
    potrzebna_ilość NUMERIC(10,2) NOT NULL,
    czy_w_koszyku BOOLEAN NOT NULL DEFAULT FALSE,
    czy_kupione BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE(id_produktu),
    CONSTRAINT dodatnia_potrzebna_ilość 
        CHECK (potrzebna_ilość>0)
);

CREATE TABLE Składniki_przepisów(
    id_przepisu INT REFERENCES Przepisy(id_przepisu),
    id_produktu INT REFERENCES Produkty(id_produktu),
    potrzebna_ilość NUMERIC(10,2) NOT NULL,
    CONSTRAINT składniki_pk 
        PRIMARY KEY(id_przepisu, id_produktu),
    CONSTRAINT dodatnia_potrzebna_ilość
        CHECK (potrzebna_ilość>0)
);

CREATE TABLE Zaplanowany_posiłek(
    id_posiłku INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_przepisu INT NOT NULL REFERENCES Przepisy(id_przepisu),
    liczba_osób NUMERIC(2) NOT NULL,
    data_posiłku DATE,
    czy_ugotowane BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT dodatnia_liczba_osób
        CHECK (liczba_osób>0)
);


/*function accepting the number of people, recipe id and optionally a date,
adds the recipe to the list of planned meals,
calculates how much of each ingredient is needed (taking into account what
is already in the pantry) and adds the missing ones to the shopping list*/
CREATE OR REPLACE PROCEDURE zaplanuj_posiłek(
    f_liczba_osób NUMERIC(2),
    f_id_przepisu INT,
    f_data_posiłku DATE DEFAULT NULL
)
language plpgsql
as $$
DECLARE
    składnik Składniki_przepisów%rowtype;
    ilość NUMERIC(10,2);
    mnożnik NUMERIC;
    aktualna_ilość NUMERIC(10,2);
BEGIN
    INSERT INTO Zaplanowany_posiłek(id_przepisu, liczba_osób, data_posiłku)
    VALUES(f_id_przepisu, f_liczba_osób, f_data_posiłku);
    SELECT f_liczba_osób::NUMERIC/liczba_porcji::NUMERIC INTO mnożnik FROM Przepisy WHERE id_przepisu = f_id_przepisu;
    FOR składnik IN (SELECT * FROM Składniki_przepisów WHERE id_przepisu = f_id_przepisu) LOOP
        ilość := składnik.potrzebna_ilość*mnożnik;
        IF składnik.id_produktu IN (SELECT id_produktu FROM Lista_zakupów WHERE czy_kupione = FALSE) THEN
            UPDATE Lista_zakupów SET potrzebna_ilość = potrzebna_ilość+ilość WHERE id_produktu = składnik.id_produktu AND czy_kupione = FALSE;
        ELSE
            SELECT COALESCE(pozostała_ilość - rezerwowana_ilość, 0) INTO aktualna_ilość FROM Spiżarnia WHERE id_produktu = składnik.id_produktu;
            aktualna_ilość := COALESCE(aktualna_ilość, 0);
            IF aktualna_ilość < ilość THEN
                INSERT INTO Lista_zakupów(id_produktu, potrzebna_ilość) VALUES(składnik.id_produktu, ilość - aktualna_ilość);
            END IF;
        END IF;
        INSERT INTO Spiżarnia(id_produktu, pozostała_ilość, rezerwowana_ilość)
        VALUES(składnik.id_produktu, 0, ilość)
        ON CONFLICT (id_produktu) 
        DO UPDATE SET rezerwowana_ilość = Spiżarnia.rezerwowana_ilość + EXCLUDED.rezerwowana_ilość;
    END LOOP;       
END $$;


/*trigger which, after removing a planned meal from the list, also removes
the appropriate amount of each ingredient from reserved products in the pantry
and removes the appropriate amount from the shopping list, if the user hasn't bought
the product yet (if already bought, nothing happens, they will have it as a spare)*/
CREATE OR REPLACE FUNCTION trigger_function0()
    RETURNS TRIGGER
    LANGUAGE PLPGSQL
AS $$
DECLARE
    składnik Składniki_przepisów%rowtype;
    ilość NUMERIC(10,2);
    mnożnik NUMERIC;
    aktualna_ilość NUMERIC(10,2);
BEGIN
    IF OLD.czy_ugotowane IS TRUE THEN --just in case
            RETURN OLD;
        END IF;
    SELECT OLD.liczba_osób::NUMERIC/liczba_porcji::NUMERIC INTO mnożnik FROM Przepisy WHERE id_przepisu = OLD.id_przepisu;
    FOR składnik IN (SELECT * FROM Składniki_przepisów WHERE id_przepisu = OLD.id_przepisu) LOOP
        ilość := składnik.potrzebna_ilość*mnożnik;
        IF składnik.id_produktu IN (SELECT id_produktu FROM Lista_zakupów WHERE czy_kupione = FALSE) THEN
            SELECT potrzebna_ilość INTO aktualna_ilość FROM Lista_zakupów WHERE id_produktu = składnik.id_produktu AND czy_kupione = FALSE;
            IF aktualna_ilość <= ilość THEN
                DELETE FROM Lista_zakupów WHERE id_produktu = składnik.id_produktu AND czy_kupione = FALSE;
            ELSE
                UPDATE Lista_zakupów SET potrzebna_ilość = Lista_zakupów.potrzebna_ilość-ilość WHERE id_produktu = składnik.id_produktu AND czy_kupione = FALSE;
            END IF;
        END IF;
        UPDATE Spiżarnia SET rezerwowana_ilość = GREATEST(0, Spiżarnia.rezerwowana_ilość - ilość) WHERE id_produktu = składnik.id_produktu;
    END LOOP;
    RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER trigger_usuwaj_plan
    AFTER DELETE ON Zaplanowany_posiłek
    FOR EACH ROW
        EXECUTE FUNCTION trigger_function0();


/*trigger which, after changing czy_kupione in the shopping list to true,
adds it to the pantry and removes it*/
CREATE OR REPLACE FUNCTION trigger_function1()
    RETURNS TRIGGER
    LANGUAGE PLPGSQL
AS $$
BEGIN
    IF NEW.czy_kupione = TRUE AND OLD.czy_kupione = FALSE THEN
        INSERT INTO Spiżarnia(id_produktu, pozostała_ilość, rezerwowana_ilość)
        VALUES(NEW.id_produktu, NEW.potrzebna_ilość, 0)
        ON CONFLICT (id_produktu)
        DO UPDATE SET pozostała_ilość = Spiżarnia.pozostała_ilość + EXCLUDED.pozostała_ilość;
        DELETE FROM Lista_zakupów WHERE id_zakupu = NEW.id_zakupu;
    END IF;
    return NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trigger_kupione
    AFTER UPDATE ON Lista_zakupów
    FOR EACH ROW
        EXECUTE FUNCTION trigger_function1();


/*trigger that ensures at least one ingredient always remains when deleting ingredients*/
CREATE OR REPLACE FUNCTION blokuj_ostatni_skladnik()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM składniki_przepisów WHERE id_przepisu = OLD.id_przepisu) = 0 THEN
        RAISE EXCEPTION 'Cannot delete the last ingredient!';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ostatni_skladnik
AFTER DELETE ON składniki_przepisów
FOR EACH ROW EXECUTE FUNCTION blokuj_ostatni_skladnik();



/*trigger which, after changing czy_ugotowane to true in the planned meals list,
removes the used ingredients (aborts if there is not enough)
and removes the reserved ingredients*/
CREATE OR REPLACE FUNCTION trigger_function2()
    RETURNS TRIGGER
    LANGUAGE PLPGSQL
AS $$
DECLARE
    składnik RECORD;
    ilość NUMERIC(10,2);
    mnożnik NUMERIC;
    aktualna_ilość NUMERIC(10,2);
BEGIN
    IF NEW.czy_ugotowane = TRUE AND OLD.czy_ugotowane = FALSE THEN
        SELECT NEW.liczba_osób::NUMERIC/liczba_porcji::NUMERIC INTO mnożnik FROM Przepisy WHERE id_przepisu = NEW.id_przepisu;
        FOR składnik IN (SELECT * FROM Składniki_przepisów s JOIN Produkty p ON s.id_produktu = p.id_produktu WHERE s.id_przepisu = NEW.id_przepisu) LOOP
            ilość := składnik.potrzebna_ilość*mnożnik;
            SELECT pozostała_ilość INTO aktualna_ilość FROM Spiżarnia WHERE id_produktu = składnik.id_produktu;
            IF aktualna_ilość IS NULL OR aktualna_ilość < ilość THEN
                Raise Exception 'Cannot cook this dish, not enough of ingredient %! (You have: %, you need: %)', składnik.nazwa, COALESCE(aktualna_ilość, 0), ilość;
            ELSE
                UPDATE Spiżarnia SET pozostała_ilość = pozostała_ilość - ilość, rezerwowana_ilość = rezerwowana_ilość - ilość WHERE id_produktu = składnik.id_produktu;
            END IF;
        END LOOP;
    END IF;
    return NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trigger_ugotowane
    BEFORE UPDATE ON Zaplanowany_posiłek
    FOR EACH ROW
        EXECUTE FUNCTION trigger_function2();


/*trigger that automatically calculates the number of calories per person in a recipe,
if the option to count it is checked and the ingredients have a calorie count per ref. amount*/
CREATE OR REPLACE FUNCTION trigger_function3()
    RETURNS TRIGGER
    LANGUAGE PLPGSQL
AS $$
DECLARE
    nazwa_brakującego_produktu VARCHAR(40);
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        SELECT p.nazwa INTO nazwa_brakującego_produktu FROM nowe_skladniki n
        JOIN Produkty p ON n.id_produktu = p.id_produktu
        WHERE (p.kcal_na_ilość_ref IS NULL OR p.ilość_ref IS NULL OR p.ilość_ref = 0)
        LIMIT 1; --takes only the first product
        IF nazwa_brakującego_produktu IS NOT NULL THEN
            RAISE EXCEPTION 'Ingredient % does not have a given reference amount or kcal per reference amount, the recipe''s caloric value cannot be calculated!', nazwa_brakującego_produktu;
            END IF;
    END IF;
    
-- CASE A: ADDING
        IF (TG_OP = 'INSERT') THEN
        UPDATE Przepisy pr SET kcal_na_osobę = sub.nowe_kcal FROM (
            SELECT s.id_przepisu, ROUND(SUM(s.potrzebna_ilość * p.kcal_na_ilość_ref / p.ilość_ref) / pr_in.liczba_porcji, 0) as nowe_kcal
            FROM Składniki_przepisów s
            JOIN Produkty p ON s.id_produktu = p.id_produktu
            JOIN Przepisy pr_in ON s.id_przepisu = pr_in.id_przepisu
            WHERE s.id_przepisu IN (SELECT id_przepisu FROM nowe_skladniki)
            GROUP BY s.id_przepisu, pr_in.liczba_porcji
        ) sub WHERE pr.id_przepisu = sub.id_przepisu AND pr.czy_liczyć_kcal = TRUE;
    END IF;
    
    -- CASE B: DELETING
        IF (TG_OP = 'DELETE') THEN
        UPDATE Przepisy pr SET kcal_na_osobę = sub.nowe_kcal FROM (
            SELECT s.id_przepisu, ROUND(SUM(s.potrzebna_ilość * p.kcal_na_ilość_ref / p.ilość_ref) / pr_in.liczba_porcji, 0) as nowe_kcal
            FROM Składniki_przepisów s
            JOIN Produkty p ON s.id_produktu = p.id_produktu
            JOIN Przepisy pr_in ON s.id_przepisu = pr_in.id_przepisu
            WHERE s.id_przepisu IN (SELECT id_przepisu FROM stare_skladniki)
            GROUP BY s.id_przepisu, pr_in.liczba_porcji
        ) sub WHERE pr.id_przepisu = sub.id_przepisu AND pr.czy_liczyć_kcal = TRUE;
        END IF;

    -- CASE C: UPDATING (we use both tables)
        IF (TG_OP = 'UPDATE') THEN
        UPDATE Przepisy pr SET kcal_na_osobę = sub.nowe_kcal FROM (
            SELECT s.id_przepisu, ROUND(SUM(s.potrzebna_ilość * p.kcal_na_ilość_ref / p.ilość_ref) / pr_in.liczba_porcji, 0) as nowe_kcal
            FROM Składniki_przepisów s
            JOIN Produkty p ON s.id_produktu = p.id_produktu
            JOIN Przepisy pr_in ON s.id_przepisu = pr_in.id_przepisu
            WHERE s.id_przepisu IN (SELECT id_przepisu FROM nowe_skladniki UNION SELECT id_przepisu FROM stare_skladniki)
            GROUP BY s.id_przepisu, pr_in.liczba_porcji
        ) sub WHERE pr.id_przepisu = sub.id_przepisu AND pr.czy_liczyć_kcal = TRUE;
        END IF;

    RETURN NULL;
END;
$$;
        
CREATE OR REPLACE TRIGGER trigger_kalorie_insert
    AFTER INSERT ON Składniki_przepisów
    REFERENCING NEW TABLE AS nowe_skladniki
    FOR EACH STATEMENT 
        EXECUTE FUNCTION trigger_function3();

CREATE OR REPLACE TRIGGER trigger_kalorie_delete
    AFTER DELETE ON Składniki_przepisów
    REFERENCING OLD TABLE AS stare_skladniki
    FOR EACH STATEMENT 
        EXECUTE FUNCTION trigger_function3();

CREATE OR REPLACE TRIGGER trigger_kalorie_update
    AFTER UPDATE ON Składniki_przepisów
    REFERENCING NEW TABLE AS nowe_skladniki OLD TABLE AS stare_skladniki
    FOR EACH STATEMENT 
        EXECUTE FUNCTION trigger_function3();



/*We insert available units and sample products.*/
INSERT INTO Jednostki (nazwa) VALUES ('g'), ('ml'), ('pieces');
INSERT INTO Produkty (nazwa, kcal_na_ilość_ref, ilość_ref, id_jednostki) VALUES
('Wheat flour', 348, 100, 1),
('White rice', 350, 100, 1),
('White sugar', 387, 100, 1),
('Buckwheat groats', 346, 100, 1),
('Oatmeal', 366, 100, 1),
('Table salt', 0, 100, 1),
('Rapeseed oil', 884, 100, 2),
('Olive oil', 882, 100, 2),
('Orange juice', 45, 100, 2),
('Mineral water', 0, 100, 2),
('Dry wine', 68, 100, 2),
('Egg (size L)', 78, 1, 3),
('Bouillon cube', 30, 1, 3),
('Fresh yeast (cube)', 320, 1, 3),
('Butter extra', 717, 100, 1),
('Chicken breast', 110, 100, 1),
('Lean cottage cheese', 98, 100, 1),
('Gouda cheese', 350, 100, 1),
('Natural yogurt', 61, 100, 1),
('Potatoes', 77, 100, 1),
('Onion', 40, 100, 1),
('Tomatoes', 18, 100, 1),
('Apple', 52, 100, 1),
('Banana', 89, 100, 1),
('Semolina', 348, 100, 1),
('Couscous', 360, 100, 1),
('Red lentils', 341, 100, 1),
('Chickpeas (dry)', 364, 100, 1),
('Spaghetti (pasta)', 350, 100, 1),
('Quinoa', 368, 100, 1),
('Walnuts', 654, 100, 1),
('Almonds', 579, 100, 1),
('Chia seeds', 486, 100, 1),
('Pumpkin seeds', 559, 100, 1),
('Raisins', 299, 100, 1),
('Cream 30%', 292, 100, 2),
('Coconut milk', 197, 100, 2),
('Soy sauce', 53, 100, 2),
('Apple cider vinegar', 21, 100, 2),
('Tomato passata', 24, 100, 2),
('Fresh salmon', 208, 100, 1),
('Minced beef', 250, 100, 1),
('Tuna in brine', 116, 100, 1),
('Poultry ham', 105, 100, 1),
('Mozzarella cheese', 280, 100, 1),
('Mayonnaise', 680, 100, 1),
('Avocado', 160, 100, 1),
('Carrot', 41, 100, 1),
('Fresh spinach', 23, 100, 1),
('Red bell pepper', 31, 100, 1),
('Garlic clove', 5, 1, 3),
('Kaiser roll', 150, 1, 3),
('Tortilla (wrap)', 170, 1, 3),
('Lemon', 30, 1, 3),
('Apple (medium)', 94, 1, 3),
('Banana (medium)', 105, 1, 3),
('Tomato (medium)', 32, 1, 3),
('Onion (medium)', 32, 1, 3),
('Potato (medium)', 65, 1, 3),
('Carrot (medium)', 18, 1, 3),
('Avocado (piece)', 240, 1, 3),
('Milk 3.2%', 65, 100, 2);
INSERT INTO Typy_dania (nazwa) VALUES ('breakfast'), ('lunch'), ('dinner'), ('dessert'), ('pastry'), ('soup'), ('snack');