# Kitchen Planner web application
## Project description
This web application was created to help
in the daily management of a home kitchen. The app's content is 
written in Polish. It consists of four main modules that work together:
- "Spiżarnia" = Pantry - allows monitoring the amount of products 
  owned in the kitchen and adding new types of products
- "Przepisy" = Recipes - list of available recipes with the possibility of adding
  new ones
- "Lista zakupów" = Shopping List - self-generated list based on 
  planned meals with the possibility of manually adding 
  additional products
- "Planer posiłków" = Meal Planner - allows planning the menu for
  the upcoming days
## Technologies used
The project was created using:
- Python 3.12.3
- Flask 3.1.2
- Flask-SQLAlchemy 3.1.1
- Jinja2 3.1.6
- PostgreSQL 16.11
- HTML5, CSS3
- Bootstrap 5 (Bootswatch Theme - Minty)
- Google Fonts (Montserrat & Kalam)
## How to run (Linux)
To run the application on your computer:
1. Create your own virtual environment by typing in the terminal:
   python -m venv venv
2. Activate the environment:
   source venv/bin/activate
3. Install all needed libraries:
   pip install -r requirements.txt
4. Configure the database:
  - run the PostgreSQL server and create a new database:
    CREATE DATABASE kuchnia_db;
  - copy the .env.example file:
    cp .env.example .env
  - fill in your username and password in this file
  - initialize the database schema in PostgreSQL:
    psql -U YOUR_USERNAME -d kuchnia_db -f path_to_file/model_logiczny.sql
5. Run the application:
   python app.py