from flask import Flask, render_template, request
from locations import states_cities, city_coordinates
from utils import fetch_data_and_predict

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html', locations=states_cities)

@app.route('/predict', methods=['POST'])
def predict():
    state = request.form['state']
    city = request.form['city']
    
    # Correct way to access the coordinates
    coords = city_coordinates.get((state, city))

    if not coords:
        return "Coordinates not found for selected location."

    # Fetch predictions using the coordinates
    predictions = fetch_data_and_predict(coords['lat'], coords['lon'])
    return render_template('result.html', city=city, predictions=predictions)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
