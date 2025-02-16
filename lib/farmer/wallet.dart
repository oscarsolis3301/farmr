import 'package:farmr_client/blockchain.dart';
import 'package:universal_io/io.dart' as io;

import 'package:logging/logging.dart';

final log = Logger('FarmerWallet');

class Wallet {
  Blockchain blockchain;

  //wallet balance
  double _balance = -1.0; //-1.0 is default value if disabled
  double get balance => _balance; //hides balance if string

  //final DateTime currentTime = DateTime.now();
  int _syncedBlockHeight = 0;

  int _lastBlockFarmed = 0;

  double _daysSinceLastBlock = 0;
  double get daysSinceLastBlock => (_daysSinceLastBlock == 0)
      ? _estimateLastFarmedTime()
      : _daysSinceLastBlock;

  Wallet(this._balance, this._daysSinceLastBlock, this.blockchain);

  void parseWalletBalance(
      String binPath, int lastBlockFarmed, bool showWalletBalance) {
    _lastBlockFarmed = lastBlockFarmed;

    var walletOutput =
        io.Process.runSync(binPath, const ["wallet", "show"]).stdout.toString();

    if (showWalletBalance) {
      try {
        //If user enabled showWalletBalance then parses ``chia wallet show``
        RegExp walletRegex = RegExp(
            "-Total Balance:(.*)${this.blockchain.currencySymbol.toLowerCase()} \\(([0-9]+) ${this.blockchain.minorCurrencySymbol.toLowerCase()}\\)",
            multiLine: false);
        //converts minor symbol to major symbol
        _balance =
            int.parse(walletRegex.firstMatch(walletOutput)?.group(2) ?? '-1') /
                1e12;
      } catch (e) {
        log.warning("Error: could not parse wallet balance.");
      }
    }

    //tries to get synced wallet height
    try {
      RegExp walletHeightRegex =
          RegExp("Wallet height: ([0-9]+)", multiLine: false);
      _syncedBlockHeight = int.parse(
          walletHeightRegex.firstMatch(walletOutput)?.group(1) ?? '-1');
    } catch (e) {
      log.warning("Error: could not parse wallet height");
    }
  }

  double getCurrentEffort(double etw, double farmedTimeDays) {
    if (etw > 0 && daysSinceLastBlock > 0) {
      //if user has not found a block then it will assume that effort starts counting from when it began farming
      double percentage = (farmedTimeDays > daysSinceLastBlock)
          ? 100 * (daysSinceLastBlock / etw)
          : 100 * (farmedTimeDays / etw);
      return percentage;
    }
    return 0.0;
  }

  double _estimateLastFarmedTime() {
    int blockDiff = _syncedBlockHeight - _lastBlockFarmed;

    int blocksPerDay = 32 * 6 * 24;

    //estimate of number of days ago, it tends to exaggerate
    double numberOfDays = (blockDiff / blocksPerDay);

    return numberOfDays;
  }
}
