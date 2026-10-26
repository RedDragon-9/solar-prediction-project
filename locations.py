import csv, os
from collections import defaultdict

def load_indian_cities():
    states_cities = defaultdict(list)
    city_coordinates = {}

    base_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(base_dir, 'indian_cities.csv')

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            city = row['City'].strip()
            state = row['State'].strip()
            lat = float(row['Latitude'])
            lon = float(row['Longitude'])

            if city not in states_cities[state]:
                states_cities[state].append(city)
                city_coordinates[(state, city)] = {'lat': lat, 'lon': lon}

    # Sort city names alphabetically
    for state in states_cities:
        states_cities[state].sort()

    return dict(states_cities), city_coordinates

# Initialize when module is loaded
states_cities, city_coordinates = load_indian_cities()
