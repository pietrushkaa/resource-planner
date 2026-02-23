# Aplikacja webowa Planer Kuchenny
## Opis projektu
Ta aplikacja webowa została stworzona, żeby pomóc
w codzienym zarządzaniu kuchnią domową. Składa się
z czterech głównych modułów, które współpracują ze sobą:
- Spiżarnia - umożliwia monitorowanie ilości produktów 
  posiadanych w kuchni i dodawanie nowych rodzajów produktów
- Przepisy - lista dostępnych przepisów z możliwością dodawania
  nowych
- Lista Zakupów - samoistnie generowana lista na podstawie 
  zaplanowanych posiłków z możliwością samodzielnego dodania 
  dodatkowych produktów
- Planer Posiłków - umożliwia planowanie jadłospisu na
  nadchodzące dni
## Użyte technologie
Projekt został utworzony przy pomocy:
- Python 3.12.3
- Flask 3.1.2
- Flask-SQLAlchemy 3.1.1
- Jinja2 3.1.6
- PostgreSQL 16.11
- HTML5, CSS3
- Bootstrap 5 (Motyw Bootswatch - Minty)
- Google Fonts (Montserrat & Kalam)
## Sposób uruchomienia (Linux)
Żeby uruchomić aplikację na swoim komputerze:
1. Stwórz własne środowisko wirtualne, wpisując w terminalu:
   python -m venv venv
2. Aktywuj środowisko:
   source venv/bin/activate
3. Zainstaluj wszystkie potrzebne biblioteki:
   pip install -r requirements.txt
4. Skonfiguruj bazę danych:
  - uruchom serwer PostgreSQL i stwórz nową bazę:
    CREATE DATABASE kuchnia_db;
  - skopiuj plik .env.example:
    cp .env.example .env
  - uzupełnij w tym pliku swoją nazwę uzytkownika i hasło
  - zainicjalizuj schemat bazy danych w PostgreSQL:
    psql -U TWOJ_UZYTKOWNIK -d kuchnia_db -f sciezka_do_pliku/model_logiczny.sql
5. Uruchom aplikację:
   python app.py