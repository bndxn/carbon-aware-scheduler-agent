from app import return_zero


def test_return_zero() -> None:
    assert return_zero(1) == 0
    assert return_zero(0) == 0
    assert return_zero(-1) == 0
