import requests, os
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from sklearn.ensemble import VotingRegressor, RandomForestRegressor, GradientBoostingRegressor
from sklearn.linear_model import Ridge

API_KEY = os.environ.get('WEATHER_API_KEY', '7701ec6e10894de99a6152246261106')

def fetch_weather_forecast(lat, lon):
    url = f'http://api.weatherapi.com/v1/forecast.json?key={API_KEY}&q={lat},{lon}&days=7'
    response = requests.get(url)
    data = response.json()
    
    print(data)
    # Debug: check if 'forecast' is present
    if 'forecast' not in data:
        print("WeatherAPI Error Response:", data)
        raise ValueError(f"API error: {data.get('error', {}).get('message', 'Unknown error')}")

    forecast_days = data['forecast']['forecastday']

    future_data = []
    for day in forecast_days:
        date = datetime.strptime(day['date'], '%Y-%m-%d')
        day_info = day['day']
        future_data.append({
            'date': day['date'],
            'dayofyear': date.timetuple().tm_yday,
            'uv': day_info.get('uv', 5),
            'cloud': day_info.get('cloud', 50)
        })
    return pd.DataFrame(future_data)


def simulate_historical_data():
    days = [datetime.today() - timedelta(days=i) for i in range(180)]
    data = []
    for d in days:
        doy = d.timetuple().tm_yday
        uv = np.clip(5 + np.sin(2 * np.pi * doy / 365) * 2 + np.random.normal(0, 0.5), 0, 11)
        cloud = np.clip(50 + np.random.normal(0, 20), 0, 100)
        irradiance = max(0, 1000 * (uv / 11) * (1 - cloud / 100))  # simulate irradiance using UV and cloud
        data.append({'dayofyear': doy, 'uv': uv, 'cloud': cloud, 'irradiance': irradiance})
    return pd.DataFrame(data)

def fetch_data_and_predict(lat, lon):
    # Simulated historical data
    historical_df = simulate_historical_data()
    X = historical_df[['dayofyear', 'uv', 'cloud']]
    y = historical_df['irradiance']

    # Train model
    model = VotingRegressor([('rf', RandomForestRegressor()), 
                             ('gb', GradientBoostingRegressor()), 
                             ('ridge', Ridge())])
    model.fit(X, y)

    # Get future weather data
    future_df = fetch_weather_forecast(lat, lon)
    X_future = future_df[['dayofyear', 'uv', 'cloud']]

    # Predict irradiance
    predictions = model.predict(X_future)
    future_df['predicted_irradiance'] = [round(p, 2) if p is not None else 0 for p in predictions]

    return future_df[['date', 'predicted_irradiance']].to_dict(orient='records')
