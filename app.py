from flask import Flask, render_template, request, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import CheckConstraint
from sqlalchemy.exc import IntegrityError
from decimal import Decimal
from datetime import datetime
from sqlalchemy import text
import os 
from dotenv import load_dotenv
load_dotenv(override=True)
app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'domyslny-klucz')
# database connection
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')

db = SQLAlchemy(app)


# table models
class Jednostka(db.Model):
    __tablename__ = 'jednostki'
    id_jednostki = db.Column(db.Integer, primary_key=True)
    nazwa = db.Column(db.String(30), nullable=False, unique=True)
    produkty = db.relationship('Produkt', backref='jednostka', lazy=True)

class TypDania(db.Model):
    __tablename__ = 'typy_dania'
    nazwa = db.Column(db.String(30), primary_key=True)
    przepisy = db.relationship('Przepis', backref='typ', lazy=True)

class Produkt(db.Model):
    __tablename__ = 'produkty'
    id_produktu = db.Column(db.Integer, primary_key=True)
    nazwa = db.Column(db.String(40), nullable=False, unique=True)
    kcal_na_ilość_ref = db.Column(db.Numeric(10, 2))
    ilość_ref = db.Column(db.Numeric(5))
    id_jednostki = db.Column(db.Integer, db.ForeignKey('jednostki.id_jednostki'), nullable=False)
    
    spiżarnia = db.relationship('Spiżarnia', backref='produkt', uselist=False)
    lista_zakupów = db.relationship('ListaZakupów', backref='produkt', uselist=False)

    __table_args__ = (
        CheckConstraint('kcal_na_ilość_ref >= 0', name='nieujemne_kcal'),
        CheckConstraint('ilość_ref > 0', name='dodatnia_ilość_ref'),
    )

class SkładnikPrzepisu(db.Model):
    __tablename__ = 'składniki_przepisów'
    id_przepisu = db.Column(db.Integer, db.ForeignKey('przepisy.id_przepisu'), primary_key=True)
    id_produktu = db.Column(db.Integer, db.ForeignKey('produkty.id_produktu'), primary_key=True)
    potrzebna_ilość = db.Column(db.Numeric(10, 2), nullable=False)
    produkt = db.relationship('Produkt')
    __table_args__ = (
        CheckConstraint('potrzebna_ilość > 0', name='dodatnia_potrzebna_ilość'),
    )

class Przepis(db.Model):
    __tablename__ = 'przepisy'
    id_przepisu = db.Column(db.Integer, primary_key=True)
    nazwa = db.Column(db.String(50), nullable=False, unique=True)
    opis = db.Column(db.Text)
    czas_przygotowania = db.Column(db.Numeric(4), nullable=False)
    liczba_porcji = db.Column(db.Numeric(2), nullable=False)
    typ_dania = db.Column(db.String(30), db.ForeignKey('typy_dania.nazwa'), nullable=False)
    kcal_na_osobę = db.Column(db.Numeric(4))
    czy_liczyć_kcal = db.Column(db.Boolean, nullable=False, default=False)
    składniki = db.relationship('SkładnikPrzepisu', backref='przepis', cascade="all, delete-orphan")
    posiłki = db.relationship('ZaplanowanyPosiłek', backref='przepis', cascade="all, delete-orphan")
    __table_args__ = (
        CheckConstraint('czas_przygotowania > 0', name='dodatni_czas_przygotowania'),
        CheckConstraint('liczba_porcji > 0', name='dodatnia_liczba_porcji'),
        CheckConstraint('kcal_na_osobę >= 0', name='dodatni_kcal_na_osobę'),
    )

class Spiżarnia(db.Model):
    __tablename__ = 'spiżarnia'
    id_produktu = db.Column(db.Integer, db.ForeignKey('produkty.id_produktu'), primary_key=True)
    pozostała_ilość = db.Column(db.Numeric(10, 2), nullable=False)
    priorytet = db.Column(db.Boolean, nullable=False, default=False)
    rezerwowana_ilość = db.Column(db.Numeric(10, 2), nullable=False, default=0)

    __table_args__ = (
        CheckConstraint('pozostała_ilość >= 0', name='nieujemna_pozostała_ilość'),
    )

class ListaZakupów(db.Model):
    __tablename__ = 'lista_zakupów'
    id_zakupu = db.Column(db.Integer, primary_key=True)
    id_produktu = db.Column(db.Integer, db.ForeignKey('produkty.id_produktu'), nullable=False, unique=True)
    potrzebna_ilość = db.Column(db.Numeric(10, 2), nullable=False)
    czy_w_koszyku = db.Column(db.Boolean, nullable=False, default=False)
    czy_kupione = db.Column(db.Boolean, nullable=False, default=False)

    __table_args__ = (
        CheckConstraint('potrzebna_ilość > 0', name='dodatnia_potrzebna_ilość'),
    )

class ZaplanowanyPosiłek(db.Model):
    __tablename__ = 'zaplanowany_posiłek'
    id_posiłku = db.Column(db.Integer, primary_key=True)
    id_przepisu = db.Column(db.Integer, db.ForeignKey('przepisy.id_przepisu'), nullable=False)
    liczba_osób = db.Column(db.Numeric(2), nullable=False)
    data_posiłku = db.Column(db.Date)
    czy_ugotowane = db.Column(db.Boolean, nullable=False, default=False)

    __table_args__ = (
        CheckConstraint('liczba_osób > 0', name='dodatnia_liczba_osób'),
    )


# index
@app.route('/')
def index():
    
    return render_template('index.html')

# adding new products
@app.route('/produkty/nowy', methods=['POST'])
def dodaj_definicje_produktu():
    nazwa = request.form.get('nazwa')
    kcal = request.form.get('kcal', type=float)
    ilość_ref = request.form.get('ilosc_ref', type=float)
    id_j = request.form.get('id_jednostki')
    
    try:
        nowy = Produkt(nazwa=nazwa, kcal_na_ilość_ref=kcal, ilość_ref=ilość_ref, id_jednostki=id_j)
        db.session.add(nowy)
        db.session.commit()
        flash(f"Product {nazwa} has been added to the database!", "success")
    except IntegrityError as blad:
        db.session.rollback()
        error_info = str(blad.orig)
        if 'nieujemne_kcal' in error_info:
            flash("Error: the number of kcal cannot be negative!", "danger")
        elif 'dodatnia_ilość_ref' in error_info:
            flash("Error: the reference quantity must be positive!", "danger")
        elif Produkt.query.filter_by(nazwa=nazwa).first():
            flash("Error: such a product already exists!", "danger")
        else:
            flash("Database error: failed to add a new product.", "danger")
        
    return redirect(url_for('wyswietl_spizarnie'))

# pantry
@app.route('/spizarnia', methods=['GET', 'POST'])
def wyswietl_spizarnie():
    sort_option = request.args.get('sort', 'nazwa_asc')
    query = Spiżarnia.query.join(Produkt)

    if sort_option == 'ilosc_asc':
        query = query.order_by(Spiżarnia.pozostała_ilość.asc())
    elif sort_option == 'ilosc_desc':
        query = query.order_by(Spiżarnia.pozostała_ilość.desc())
    elif sort_option == 'nazwa_desc':
        query = query.order_by(Produkt.nazwa.desc())
    elif sort_option == 'priorytet':
        query = query.order_by(Spiżarnia.priorytet.desc())
    else:
        query = query.order_by(Produkt.nazwa.asc())  # default A-Z

    zapasy = query.filter(Spiżarnia.pozostała_ilość > 0).all()

    if request.method == 'POST':
        nazwa = request.form.get('nazwa_produktu')
        ilosc = request.form.get('ilosc')
        priorytet = 'priorytet' in request.form
        prod = Produkt.query.filter_by(nazwa=nazwa).first() # looking for a product with the given name
        
        if prod:
            nowy_wpis = Spiżarnia(id_produktu=prod.id_produktu, pozostała_ilość=ilosc, priorytet=priorytet)
            db.session.add(nowy_wpis)
            try:
                db.session.commit()
            except IntegrityError as blad:
                db.session.rollback()
                error_info = str(blad.orig)
                if float(ilosc) < 0:
                    flash("Error: quantity cannot be negative!", "danger")
                elif Spiżarnia.query.get(prod.id_produktu):
                    Spiżarnia.query.get(prod.id_produktu).pozostała_ilość += Decimal(ilosc)
                    db.session.commit()
                else:
                    flash("Database error: Incorrect data.", "danger")

        else:
            flash("Enter a valid product name or create a new one!", "warning")
            
        return redirect(url_for('wyswietl_spizarnie'))
    wszystkie_produkty = Produkt.query.all()
    wszystkie_jednostki = Jednostka.query.all()
    return render_template('spizarnia.html', produkty=zapasy, lista_produktow=wszystkie_produkty, jednostki=wszystkie_jednostki)

@app.route('/usun/<int:id_prod>', methods=['POST'])
def usun_ze_spizarni(id_prod):
    wpis = Spiżarnia.query.get(id_prod) # find product in the pantry
    if wpis:
        db.session.delete(wpis)
        db.session.commit()
    return redirect(url_for('wyswietl_spizarnie'))

@app.route('/zmien_ilosc/<int:id_prod>', methods=['POST'])
def zmien_ilosc(id_prod):
    nowa_ilosc = request.form.get('nowa_ilosc')
    wpis = Spiżarnia.query.get(id_prod)
    
    if wpis and nowa_ilosc:
        if float(nowa_ilosc) < 0:
            flash("Quantity cannot be negative!", "danger")
        else:
            wpis.pozostała_ilość = float(nowa_ilosc)
            db.session.commit()
    
    return redirect(url_for('wyswietl_spizarnie'))


# recipes
@app.route('/przepisy/nowy', methods=['POST'])
def dodaj_nowy_przepis():
    nazwa = request.form.get('nazwa')
    typ_dania = request.form.get('typ_dania')
    czas_przygotowania = request.form.get('czas_przygotowania', type=float)
    liczba_porcji = request.form.get('liczba_porcji', type=float)
    opis = request.form.get('opis')
    czy_kcal = 'czy_liczyc_kcal' in request.form
    produkty_ids = request.form.getlist('produkty[]')
    ilosci = request.form.getlist('ilosci[]')
    
    skuteczne_ids = [i for i in produkty_ids if i and i.strip()]
    if not skuteczne_ids or len(skuteczne_ids) != len(produkty_ids): # cannot create a recipe without ingredients
        flash("Error: one of the ingredient names was not filled in or no ingredient was added!", "danger")
    else:
        try:
            nowy_przepis = Przepis(nazwa=nazwa, typ_dania=typ_dania, czas_przygotowania=czas_przygotowania, liczba_porcji=liczba_porcji, opis=opis, czy_liczyć_kcal=czy_kcal)
            db.session.add(nowy_przepis)
            db.session.flush() # fetches the recipe ID before we commit
            for i in range(len(produkty_ids)):
                if ilosci[i]: # add only if quantity is entered
                    skladnik = SkładnikPrzepisu(
                        id_przepisu=nowy_przepis.id_przepisu,
                        id_produktu=int(produkty_ids[i]),
                        potrzebna_ilość=float(ilosci[i])
                    )
                    db.session.add(skladnik)
            db.session.commit()
        except IntegrityError as blad:
            db.session.rollback()
            error_info = str(blad.orig)
            if 'dodatnia_potrzebna_ilość' in error_info:
                flash("Error: ingredient quantity cannot be negative!", "danger")
            elif 'dodatni_czas_przygotowania' in error_info:
                flash("Error: preparation time must be positive!", "danger")
            elif 'dodatnia_liczba_porcji' in error_info:
                flash("Error: number of servings must be positive!", "danger")
            elif Przepis.query.filter_by(nazwa=nazwa).first():
                flash("Error: a recipe with this name already exists! You cannot create it.", "danger")
            else:
                flash("Database error: failed to add a new recipe.", "danger")
            
    return redirect(url_for('wyswietl_przepisy'))

@app.route('/przepisy')
def wyswietl_przepisy():
    wybrany_typ = request.args.get('typ')
    typy = TypDania.query.all()
    
    if wybrany_typ:
        lista = Przepis.query.filter_by(typ_dania=wybrany_typ).all()
    else:
        lista = Przepis.query.all()

    wszystkie_typy_dan = TypDania.query.all()
    wszystkie_produkty = Produkt.query.order_by(Produkt.nazwa.asc()).all()
    return render_template('przepisy.html', przepisy=lista, lista_produktow=wszystkie_produkty, typy_dan=wszystkie_typy_dan, wybrany_typ=wybrany_typ)

@app.route('/usun_przepis/<int:id_prze>', methods=['POST'])
def usun_przepis(id_prze):
    wpis = Przepis.query.get(id_prze) # find product in the pantry
    if wpis:
        db.session.delete(wpis)
        db.session.commit()
    return redirect(url_for('wyswietl_przepisy'))


# shopping list
@app.route('/zakupy', methods=['GET', 'POST'])
def wyswietl_zakupy():
    if request.method == 'POST':
        nazwa = request.form.get('nazwa_produktu')
        ilosc = request.form.get('ilosc')
        
        prod = Produkt.query.filter_by(nazwa=nazwa).first()
        
        if prod:
            # Checking if the product is already on the shopping list
            istniejacy_wpis = ListaZakupów.query.filter_by(id_produktu=prod.id_produktu).first()
            
            if istniejacy_wpis:
                if float(ilosc) >= 0:
                    istniejacy_wpis.potrzebna_ilość += Decimal(ilosc)
                    db.session.commit()
                else:
                    flash("Quantity cannot be negative!", "danger")
            else:
                nowy_zakup = ListaZakupów(id_produktu=prod.id_produktu, potrzebna_ilość=ilosc)
                db.session.add(nowy_zakup)
                try:
                    db.session.commit()
                except IntegrityError:
                    db.session.rollback()
                    flash("Error while adding.", "danger")
        else:
            flash("Product not found in the database!", "danger")
            
        return redirect(url_for('wyswietl_zakupy'))

    elementy_listy = ListaZakupów.query.all()
    wszystkie_produkty = Produkt.query.order_by(Produkt.nazwa.asc()).all()
    wszystkie_jednostki = Jednostka.query.all()
    return render_template('zakupy.html', zakupy=elementy_listy, lista_produktow=wszystkie_produkty, jednostki=wszystkie_jednostki)

@app.route('/zakupy/usun/<int:id_zakupu>', methods=['POST'])
def usun_z_zakupow(id_zakupu):
    wpis = ListaZakupów.query.get(id_zakupu)
    if wpis:
        db.session.delete(wpis)
        db.session.commit()
    return redirect(url_for('wyswietl_zakupy'))


@app.route('/zakupy/nowy_produkt', methods=['POST'])
def dodaj_definicje_produktu_zakupy():
    nazwa = request.form.get('nazwa')
    kcal = request.form.get('kcal', type=float)
    ilosc_ref = request.form.get('ilosc_ref', type=float)
    id_j = request.form.get('id_jednostki')
    
    try:
        nowy = Produkt(nazwa=nazwa, kcal_na_ilość_ref=kcal, ilość_ref=ilość_ref, id_jednostki=id_j)
        db.session.add(nowy)
        db.session.commit()
        flash(f"Product {nazwa} has been added to the database!", "success")
    except IntegrityError as blad:
        db.session.rollback()
        error_info = str(blad.orig)
        if 'nieujemne_kcal' in error_info:
            flash("Error: the number of kcal cannot be negative!", "danger")
        elif 'dodatnia_ilość_ref' in error_info:
            flash("Error: the reference quantity must be positive!", "danger")
        elif Produkt.query.filter_by(nazwa=nazwa).first():
            flash("Error: such a product already exists!", "danger")
        else:
            flash("Database error: failed to add a new product.", "danger")
        
    return redirect(url_for('wyswietl_zakupy'))

@app.route('/zakupy/kupione/<int:id_zakupu>', methods=['POST'])
def zmien_status_kupione(id_zakupu):
    wpis = ListaZakupów.query.get(id_zakupu)
    if wpis:
        wpis.czy_kupione = True;
        db.session.commit()
        flash("Product has been marked as purchased!", "info")
    return redirect(url_for('wyswietl_zakupy'))


# list of planned meals
@app.route('/posilki', methods=['GET','POST'])
def wyswietl_posilki():
    wszystkie_posiłki = ZaplanowanyPosiłek.query.filter_by(czy_ugotowane=False).all()
    return render_template('posilki.html', posilki=wszystkie_posiłki)

@app.route('/posilki/ugotowane/<int:id_posilku>', methods=['POST'])
def zmien_status_ugotowane(id_posilku):
    wpis = ZaplanowanyPosiłek.query.get(id_posilku)
    if wpis:
        try:
            wpis.czy_ugotowane = True;
            db.session.commit()
            flash("Meal has been marked as cooked!", "info")
            # here possibly a "cooking page" meaning a modal todo
        except:
            db.session.rollback()
            flash("Cannot cook the dish, not enough ingredients!", "danger")
            # here we could catch the exact error and state which ingredient is missing todo
    return redirect(url_for('wyswietl_posilki'))

@app.route('/posilki/usun/<int:id_posilku>', methods=['POST'])
def usun_z_planow(id_posilku):
    wpis = ZaplanowanyPosiłek.query.get(id_posilku)
    if wpis:
        db.session.delete(wpis)
        db.session.commit()
    return redirect(url_for('wyswietl_posilki'))


# meal planning
@app.route('/planowanie', methods=['GET', 'POST'])
def zaplanuj_posilek():
    if request.method == 'POST':
        id_przepisu = request.form.get('wybrany_przepis')
        liczba_osob = request.form.get('liczba_osob')
        data_posilku = request.form.get('data_posilku')

        if not id_przepisu or not liczba_osob:
            flash("Select a recipe and provide the number of people!", "warning")
            return redirect(url_for('zaplanuj_posilek'))

        data_obj = datetime.strptime(data_posilku, '%Y-%m-%d').date() if data_posilku else None  # date conversion

        try:
            # calling procedure from psql
            db.session.execute(
                text("CALL zaplanuj_posiłek(:osoby, :id_prze, :data)"),
                {
                    'osoby': int(liczba_osob),
                    'id_prze': int(id_przepisu),
                    'data': data_obj
                }
            )
            db.session.commit()
            flash("Recipe has been planned!", "success")
            return redirect(url_for('wyswietl_posilki'))
        except:
            db.session.rollback()
            flash("Database error, recipe was not planned!", "danger")

    wybrany_typ = request.args.get('typ')
    typy = TypDania.query.all()
    
    if wybrany_typ:
        przepisy_lista = Przepis.query.filter_by(typ_dania=wybrany_typ).all()
    else:
        przepisy_lista = Przepis.query.all()

    return render_template('zaplanuj.html', 
                           przepisy=przepisy_lista, 
                           typy_dan=typy, 
                           wybrany_typ=wybrany_typ)

if __name__ == "__main__":
    app.run(debug=True)