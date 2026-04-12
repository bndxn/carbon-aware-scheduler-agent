from carbon_intensity.open_meteo import (
    subsample_hourly,
    weather_wind_forecast_for_model,
)


def test_weather_requires_location() -> None:
    out = weather_wind_forecast_for_model(
        place_query=None, latitude=None, longitude=None, forecast_days=2
    )
    assert "error" in out


def test_subsample_shortens_hourly() -> None:
    hourly = {
        "time": list(range(100)),
        "wind_speed_10m": list(range(100)),
    }
    data = subsample_hourly({"hourly": hourly, "latitude": 1.0}, max_rows=10)
    h = data["hourly"]
    assert isinstance(h, dict)
    assert len(h["time"]) <= 10
    assert data.get("hourly_subsampled") is True
