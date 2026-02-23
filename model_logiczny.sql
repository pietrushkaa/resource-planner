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


/*funkcja przyjmujaca liczbę osób, id przepisu i ew. datę,
dodaje przepis na listę zaplanowanych posiłków,
oblicza ile potrzeba każdego składniku (biorąc pod uwagę ile
jest już w spiżarni) i dodaje brakujące na listę zakupów*/
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


/*trigger, który po usunięciu zaplanowanego posiłku z listy usuwa również
odpowiednią ilość każdego składnika z rezerwowanych produktów w spiżarni
oraz usuwa odpowiednią ilość z listy zakupów, jeśli użytkownik jeszcze nie kupił
produktu (jeśli już kupił, to nic się nie dzieje, będzie miał na zapas)*/
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
	IF OLD.czy_ugotowane IS TRUE THEN --na wszelki wypadek
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


/*trigger, który po zmianie czy_kupione w liście zakupów na true
dodaje go do spiżarni i go usuwa*/
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


/*trigger, który pilnuje, żeby przy usuwaniu składników zawsze pozostał conajmniej jeden*/
CREATE OR REPLACE FUNCTION blokuj_ostatni_skladnik()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT COUNT(*) FROM składniki_przepisów WHERE id_przepisu = OLD.id_przepisu) = 0 THEN
        RAISE EXCEPTION 'Nie można usunąć ostatniego składnika!';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ostatni_skladnik
AFTER DELETE ON składniki_przepisów
FOR EACH ROW EXECUTE FUNCTION blokuj_ostatni_skladnik();



/*trigger, który po zmianie czy_ugotowane na true w liście
zaplanowanych posiłków usuwa użyte składniki (przerywa gdy jest za mało)
i usuwa zarezerwowane składniki*/
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
				Raise Exception 'Nie można ugotować tego dania, za mało składnika %! (Masz: %, potrzebujesz: %)', składnik.nazwa, COALESCE(aktualna_ilość, 0), ilość;
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


/*trigger, który samodzielnie liczy liczbę kalorii na osobę w przepisie,
jeśli jest zaznaczona opcja, żeby ją liczyć oraz składniki posiadają
liczbę kalorii na ilość ref.*/
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
		LIMIT 1; --bierze tylko pierwszy produkt
		IF nazwa_brakującego_produktu IS NOT NULL THEN
			RAISE EXCEPTION 'Składnik % nie ma podanej ilości referencyjnej lub liczby kcal na ilość referencyjną, nie da się obliczyć kaloryczności przepisu!', nazwa_brakującego_produktu;
	    	END IF;
	END IF;
	
-- PRZYPADEK A: DODAWANIE
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
	
    -- PRZYPADEK B: USUWANIE
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

    -- PRZYPADEK C: AKTUALIZACJA (używamy obu tabel)
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



/*Wstawiamy dostępne jednostki i przykładowe produkty.*/
INSERT INTO Jednostki (nazwa) VALUES ('g'), ('ml'), ('sztuki');
INSERT INTO Produkty (nazwa, kcal_na_ilość_ref, ilość_ref, id_jednostki) VALUES
('Mąka pszenna', 348, 100, 1),
('Ryż biały', 350, 100, 1),
('Cukier biały', 387, 100, 1),
('Kasza gryczana', 346, 100, 1),
('Płatki owsiane', 366, 100, 1),
('Sól kuchenna', 0, 100, 1),
('Olej rzepakowy', 884, 100, 2),
('Oliwa z oliwek', 882, 100, 2),
('Sok pomarańczowy', 45, 100, 2),
('Woda mineralna', 0, 100, 2),
('Wino wytrawne', 68, 100, 2),
('Jajko (rozmiar L)', 78, 1, 3),
('Kostka bulionowa', 30, 1, 3),
('Drożdże świeże (kostka)', 320, 1, 3),
('Masło extra', 717, 100, 1),
('Pierś z kurczaka', 110, 100, 1),
('Twaróg chudy', 98, 100, 1),
('Ser żółty Gouda', 350, 100, 1),
('Jogurt naturalny', 61, 100, 1),
('Ziemniaki', 77, 100, 1),
('Cebula', 40, 100, 1),
('Pomidory', 18, 100, 1),
('Jabłko', 52, 100, 1),
('Banan', 89, 100, 1),
('Kasza manna', 348, 100, 1),
('Kuskus', 360, 100, 1),
('Soczewica czerwona', 341, 100, 1),
('Ciecierzyca (sucha)', 364, 100, 1),
('Spaghetti (makaron)', 350, 100, 1),
('Quinoa (komosa)', 368, 100, 1),
('Orzechy włoskie', 654, 100, 1),
('Migdały', 579, 100, 1),
('Nasiona chia', 486, 100, 1),
('Pestki dyni', 559, 100, 1),
('Rodzynki', 299, 100, 1),
('Śmietanka 30%', 292, 100, 2),
('Mleczko kokosowe', 197, 100, 2),
('Sos sojowy', 53, 100, 2),
('Ocet jabłkowy', 21, 100, 2),
('Passata pomidorowa', 24, 100, 2),
('Łosoś świeży', 208, 100, 1),
('Wołowina mielona', 250, 100, 1),
('Tuńczyk w sosie własnym', 116, 100, 1),
('Szynka drobiowa', 105, 100, 1),
('Ser Mozzarella', 280, 100, 1),
('Majonez', 680, 100, 1),
('Awokado', 160, 100, 1),
('Marchew', 41, 100, 1),
('Szpinak świeży', 23, 100, 1),
('Papryka czerwona', 31, 100, 1),
('Ząbek czosnku', 5, 1, 3),
('Bułka kajzerka', 150, 1, 3),
('Tortilla (placek)', 170, 1, 3),
('Cytryna', 30, 1, 3),
('Jabłko (średnie)', 94, 1, 3),
('Banan (średni)', 105, 1, 3),
('Pomidor (średni)', 32, 1, 3),
('Cebula (średnia)', 32, 1, 3),
('Ziemniak (średni)', 65, 1, 3),
('Marchew (średnia)', 18, 1, 3),
('Awokado', 240, 1, 3),
('Mleko 3.2%', 65, 100, 2);
INSERT INTO Typy_dania (nazwa) VALUES ('śniadanie'), ('obiad'), ('kolacja'), ('deser'), ('wypiek'), ('zupa'), ('przekąska');
