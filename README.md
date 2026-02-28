# Kitchen Planner web application
## Project description
This web application was created to help
in the daily management of a home kitchen. It consists of four main modules that work together (Pantry, Recipe Book, Meal Planner, Shopping List). It integrates a PostgreSQL database with advanced algorithms that automate data management, using a Python and Flask backend paired with a simple and aesthetic HTML/CSS interface.

## Modules & Interface preview
### Main Menu
- **navigation**: jump between the Pantry, Recipe Book, Meal Planner, and Shopping List

*Interface preview:*
<img src="screens/index.png" width="90%" alt="">

---
### Pantry
- **inventory tracking**: monitor the quantity of all products in your kitchen
  - sort by name, quantity or priority
  - add and delete products, change quantity
- **adding new products**: add new product types with units and caloric values

*Interface preview:*
<img src="screens/pantry.png" width="90%" alt="">

---
### Recipe Book
- **list of recipes**: view and manage your personal collection of recipes with the ability to add or delete
  - filter by meal type (e.g., Breakfast, Dinner, Snack)
- **adding new recipes**: add new recipes including list of ingredients and preparation method
  - features a PostgreSQL algorithm that adds the possibility to automatically calculate total calories per person based on the ingredient list

*Interface preview:*
<img src="screens/recipes.png" width="90%" alt="">

---
### Shopping List
- **automated list**: when you plan a meal, a PostgreSQL algorithm automatically identifies missing ingredients in your pantry and adds them to your shopping list
- **manual management**: add and delete additional products on your own

*Interface preview:*
<img src="screens/shoppinglist.png" width="90%" alt="">

---
### Meal planner
- **planning meals**: plan meals for upcoming days by selecting a recipe, the number of servings, and (additionally) a specific date
  - filter by meal type (e.g., Breakfast, Dinner, Snack) for a faster and more convenient planning
  - once a meal is marked as cooked, a PostgreSQL algorithm verifies ingredient availability and automatically deducts the required quantities from your pantry

*Interface preview of Meal Planner:*
<img src="screens/mealplanner.png" width="90%" alt="">

*Interface preview of Planning Meals Page:*
<img src="screens/planyourmeal.png" width="90%" alt="">
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
   ```
   python3 -m venv venv
   ```
2. Activate the environment:
   ```
   source venv/bin/activate
   ```
3. Install all needed libraries:
   ``` 
   pip install -r requirements.txt
   ```
4. Configure the database:
  - run the PostgreSQL server and create a new database:
    ```CREATE DATABASE kuchnia_db;```
  - create .env file with the following content:
      ```
      DATABASE_URL='postgresql://username:password@localhost:5432/kitchen_db'
      SECRET_KEY='secret-key-12345'
      ```
  - fill in your username and password in this file
  - initialize the database schema in PostgreSQL:
    ```
    psql -U YOUR_USERNAME -d kuchnia_db -f path_to_file/model_logiczny.sql
    ```
5. Run the application:
    ```
    python3 app.py
    ```