# Be name khoda

import decimal
import random
from decimal import Decimal

import matplotlib.pyplot as plt

decimal.getcontext().prec = 15


class Bancor:
    def __init__(self):
        self.dots = []

        self.supply = Decimal(1000)
        self.reserve = Decimal(100)

        self.shiftSupply = Decimal(100)
        self.shiftReverse = Decimal(1)

        self.cw = Decimal(0.35) * Decimal(10 ** 6)
        self.scale = Decimal(10 ** 6)

        self.fee = Decimal(5 * 10 ** 3)

        self.total_supply = Decimal(self.supply)
        self.total_collateral = Decimal(self.reserve)
        self.total_fee = Decimal(0)

    def price(self):
        return self.reserve / (self.supply * self.cw)

    def get_real_reserve_and_supply(self):
        reserve = self.reserve + self.shiftReverse
        supply = self.supply + self.shiftSupply
        return reserve, supply

    def calculatePurchaseReverse(self, idoAmount):
        reserve, supply = self.get_real_reserve_and_supply()
        idoAmount = Decimal(idoAmount)
        collateralAmount = reserve * ((idoAmount / supply + 1) ** (self.scale / self.cw) - 1)
        return collateralAmount * (self.scale / (self.scale - self.fee))

    def calculatePurchaseReturn(self, collateralAmount):
        reserve, supply = self.get_real_reserve_and_supply()
        collateralAmount = Decimal(collateralAmount)
        feeAmount = collateralAmount * self.fee / self.scale
        collateralAmount = collateralAmount - feeAmount
        idoAmount = supply * (((collateralAmount / reserve) + 1) ** (self.cw / self.scale) - 1)
        return idoAmount, feeAmount

    def calculateSaleReverse(self, collateralAmount):
        reserve, supply = self.get_real_reserve_and_supply()
        collateralAmount = Decimal(collateralAmount) * (self.scale / (self.scale - self.fee))
        idoAmount = supply * (1 - (1 - (collateralAmount / reserve) ** (self.cw / self.scale)))
        return idoAmount

    def calculateSaleReturn(self, idoAmount):
        reserve, supply = self.get_real_reserve_and_supply()
        idoAmount = Decimal(idoAmount)
        returnAmount = reserve * (1 - ((1 - idoAmount / supply) ** (self.scale / self.cw)))
        feeAmount = returnAmount * self.fee / self.scale
        return returnAmount - feeAmount, feeAmount

    def buy(self, _collateralAmount):
        _collateralAmount = Decimal(_collateralAmount)
        idoAmount, feeAmount = self.calculatePurchaseReturn(_collateralAmount)
        self.reserve = self.reserve + _collateralAmount - feeAmount
        self.dots += [(self.supply, self.price())]
        self.supply += idoAmount
        self.total_supply += idoAmount
        self.total_collateral += _collateralAmount - feeAmount
        self.total_fee += feeAmount
        return idoAmount

    def sell(self, idoAmount):
        idoAmount = Decimal(idoAmount)
        collateralAmount, feeAmount = self.calculateSaleReturn(idoAmount)
        self.reserve = self.reserve - (collateralAmount + feeAmount)
        self.dots += [(self.supply, self.price())]

        self.supply -= idoAmount
        self.total_supply -= idoAmount
        self.total_collateral -= (collateralAmount + feeAmount)
        self.total_fee += feeAmount
        return idoAmount

    def plot(self, style='r+', color='b'):
        supplies = [dot[0] for dot in self.dots]
        prices = [dot[1] for dot in self.dots]
        plt.plot(supplies, prices, style, color=color)

    def clearDots(self):
        self.dots = []

    def print_stats(self):
        print(f'total supply: {self.total_supply}')
        print(f'total collateral: {self.total_collateral}')
        print(f'total fee: {self.total_fee}')


class BaseTest:
    def __init__(self, bancor: Bancor, precision=4, verbose=True):
        self.bancor = bancor
        self.init_state = {}
        self.state_after_buy = {}
        self.state_after_sell = {}
        self.precision = precision
        self.verbose = verbose

    def set_state(self, state_obj):
        state_obj['total_supply'] = self.bancor.total_supply
        state_obj['total_collateral'] = self.bancor.total_collateral
        state_obj['total_fee'] = self.bancor.total_fee

    def buy(self):
        raise NotImplemented

    def sell(self):
        raise NotImplemented

    def run(self):
        if self.verbose:
            print(f'\033[92m>>> run test {self.__class__.__name__}\033[0m')
        self.set_state(self.init_state)
        if self.verbose:
            print('\033[95m' + '=' * 6 + ' init stats ' + '=' * 6 + '\033[0m')
            self.bancor.print_stats()
        self.buy()
        self.set_state(self.state_after_buy)
        if self.verbose:
            print('\033[95m' + '=' * 6 + ' stats after buy ' + '=' * 6 + '\033[0m')
            self.bancor.print_stats()
        self.sell()
        self.set_state(self.state_after_sell)
        if self.verbose:
            print('\033[95m' + '=' * 6 + ' stats after sell ' + '=' * 6 + '\033[0m')
            self.bancor.print_stats()
            print()
        if self.verbose:
            if self.is_passed():
                print('\033[94m' + '_' * 6 + ' test passed successfully ' + '_' * 6 + '\033[0m')
            else:
                print('\033[91m' + '*' * 6 + ' test failed ' + '*' * 6 + '\033[0m')
            print()

    def test(self):
        raise NotImplemented

    def is_passed(self):
        collateral_diff = self.init_state['total_collateral'] - self.state_after_sell['total_collateral']
        supply_diff = self.init_state['total_supply'] - self.state_after_sell['total_supply']
        print('\033[92m' + f'collateral_diff: {collateral_diff}, supply_diff: {supply_diff}' + '\033[0m')
        return abs(collateral_diff) <= 10 ** (-self.precision) and abs(supply_diff) <= 10 ** (-self.precision)


class SequntialBuyAndSell(BaseTest):
    def __init__(self, bancor: Bancor, total_buy=10, num_buy=1, num_sell=1, precision=1):
        super().__init__(bancor, precision)
        self.total_buy = Decimal(total_buy)
        self.num_buy = num_buy
        self.num_sell = num_sell

        self.each_buy_amount = self.total_buy / self.num_buy
        self.idoBoughtList = []
        self.collateralSoldList = []

    def buy(self):
        for _ in range(self.num_buy):
            ido = self.bancor.buy(self.each_buy_amount)
            self.idoBoughtList.append(ido)

    def sell(self):
        each_sell_amount = sum(self.idoBoughtList) / self.num_sell
        for _ in range(self.num_sell):
            collateral = self.bancor.sell(each_sell_amount)
            self.collateralSoldList.append(collateral)


class SequentialBuyAndSellWithOrder(SequntialBuyAndSell):
    def __init__(self, bancor: Bancor, total_buy=10, num_buy=1, precision=1):
        super().__init__(bancor, total_buy, num_buy, precision=precision)

    def sell(self):
        for ido in self.idoBoughtList[::-1]:
            collateral = self.bancor.sell(ido)
            self.collateralSoldList.append(collateral)


class RandomTest(BaseTest):
    def __init__(self, bancor: Bancor, precision=4):
        super().__init__(bancor, precision)

    def buy(self):
        for _ in range(100000):
            try:
                if random.random() < 0.6:
                    self.bancor.buy(random.randint(10, 100000))
                else:
                    self.bancor.sell(random.randint(1, int(self.bancor.total_supply)))
            except ValueError:
                pass

    def sell(self):
        if self.bancor.total_supply > self.init_state['total_supply']:
            self.bancor.sell(self.bancor.total_supply - self.init_state['total_supply'])
        elif self.bancor.total_collateral < self.init_state['total_collateral']:
            self.bancor.buy(self.init_state['total_collateral'] - self.bancor.total_collateral)
# t1 = SequntialBuyAndSell(Bancor(), total_buy=1000000, num_buy=1000, num_sell=2000)
# t1.verbose = True
# t1.run()


def test():
    NUM_TEST = 1000
    bancor = Bancor()
    for i in range(NUM_TEST):
        total_buy = random.randint(10*5, 10**7)
        num_buy = random.randint(1, 10**5)
        num_sell = random.randint(1, 10**5)
        # bancor = Bancor()
        print(f'test{[i]}: total_buy={total_buy}, num_buy={num_buy}, num_sell={num_sell}')
        t1 = SequntialBuyAndSell(bancor, total_buy=total_buy, num_buy=num_buy, num_sell=num_sell)
        t1.verbose = False
        t1.run()
        t2 = SequentialBuyAndSellWithOrder(bancor, total_buy=total_buy, num_buy=num_buy)
        t2.verbose = False
        t2.run()
        t3 = RandomTest(bancor)
        t3.verbose = False
        t3.run()

        bancor.print_stats()


# test()
# t = RandomTest(Bancor())
# t.run()

b = Bancor()
r, f = b.calculatePurchaseReturn(1000)
print(r, f, b.calculatePurchaseReverse(r))

r, f = b.calculateSaleReturn(1000)
print(r, f, b.calculateSaleReverse(r))