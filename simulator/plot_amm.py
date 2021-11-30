from decimal import Decimal

from simulator import Bancor
from matplotlib import pyplot as plt


def price_plot(booster, cw, first_price):
    _COLLATERAL_AMOUNT = 0.1
    b = Bancor()
    b.shiftSupply = Decimal(booster)
    b.cw = Decimal(cw) * Decimal(10 ** 6)
    b.fee = Decimal(0)
    b.shiftReserve = Decimal(first_price) / ((1 + 1 / b.shiftSupply) ** (b.scale / b.cw) - 1)
    print(b.shiftReserve)
    dots = list()
    dots.append((b.supply, b.calculatePurchaseReverse(1)))
    for _ in range(20000):
        b.buy(_COLLATERAL_AMOUNT)
        dots.append((b.supply, b.calculatePurchaseReverse(1)))
    plt.plot([dot[0] for dot in dots], [dot[1] for dot in dots])


price_plot(30, 0.15, 5)
price_plot(40, 0.15, 5)
price_plot(20, 0.15, 5)
price_plot(40, 0.25, 5)
price_plot(40, 0.15, 1)
price_plot(10, 0.15, 1)

plt.show()
