import 'dart:core';
import 'package:farmr_client/blockchain.dart';
import 'package:universal_io/io.dart' as io;
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'package:farmr_client/cache.dart';

final log = Logger('Config');

class Config {
  Cache cache;

  late Blockchain _blockchain;

  ClientType _type = ClientType.Harvester;
  ClientType get type => _type;

  //Optional, custom, user defined name
  late String _name;
  String get name => _name;

  //Optional, custom 3 letter currency
  String _currency = 'USD';
  String get currency => _currency.toUpperCase();

  String _chiaPath = '';
  String get chiaPath => _chiaPath;

  //farmed balance
  bool _showBalance = true;
  bool get showBalance => _showBalance;

  //wallet balance
  bool _showWalletBalance = false;
  bool get showWalletBalance => _showWalletBalance;

  bool _sendPlotNotifications = false; //plot notifications
  bool get sendPlotNotifications => _sendPlotNotifications;

  bool _sendDriveNotifications = true; //drive notifications
  bool get sendDriveNotifications => _sendDriveNotifications;

  bool _sendBalanceNotifications = true; //balance notifications
  bool get sendBalanceNotifications => _sendBalanceNotifications;

  bool _sendOfflineNotifications = false; //status notifications
  bool get sendOfflineNotifications => _sendOfflineNotifications;

  bool _sendStatusNotifications = true; //status notifications
  bool get sendStatusNotifications => _sendStatusNotifications;

  bool _parseLogs = false;
  bool get parseLogs => _parseLogs;

  //number of users that can link this machine
  int _userNumber = 1;
  //Sets maximum of 10 users
  int get userNumber => (_userNumber <= 10) ? _userNumber : 10;

  String _swarPath = "";
  String get swarPath => _swarPath;

  //if this is set to true then client's data will be available on public api
  bool _publicAPI = false;
  bool get publicAPI => _publicAPI;

  //allows parsing RAM content and CPU
  bool _showHardwareInfo = true;
  bool get showHardwareInfo => _showHardwareInfo;

  //Nahvan requested for a disk space override for computers in shared networks
  bool _ignoreDiskSpace = false;
  bool get ignoreDiskSpace => _ignoreDiskSpace;

  //HPOOL MODE
  String _hpoolConfigPath = "";
  String get hpoolConfigPath => _hpoolConfigPath;

  String _hpoolAuthToken = "";
  String get hpoolAuthToken => _hpoolAuthToken;

  //FOXYPOOL MODE
  String _poolPublicKey = "";
  String get poolPublicKey => _poolPublicKey;

  // '/home/user/.farmr' for package installs, '' (project path) for the rest
  late String _rootPath;
  late io.File _config;

  Config(this._blockchain, this.cache, this._rootPath,
      [isHarvester = false, isHPool = false, isFoxyPoolOG = false]) {
    _config =
        io.File(_rootPath + "config/config${_blockchain.fileExtension}.json");
    //sets default name according to client type
    if (isHarvester) {
      _type = ClientType.Harvester;
      _name = "Harvester";
    } else if (isHPool) {
      _type = ClientType.HPool;
      _name = "HPool";
    } else if (isFoxyPoolOG) {
      _type = ClientType.FoxyPoolOG;
      _name = "FoxyPool";
    } else {
      _type = ClientType.Farmer;
      _name = "Farmer";
    }
  }

  Future<void> init() async {
    //If file doesnt exist then create new config
    if (!_config.existsSync())
      await saveConfig(); //creates config file if doesnt exist
    //If file exists then loads config
    else
      _loadConfig(); //config.json

    //and asks for bin path if path is not defined/not found and is Farmer
    if ((type == ClientType.Farmer || type == ClientType.FoxyPoolOG) &&
        (cache.binPath == '' || !io.File(cache.binPath).existsSync()))
      await _askForBinPath();

    /** Generate Discord Id's */
    if (_blockchain.id.ids.length != userNumber) {
      if (userNumber > _blockchain.id.ids.length) {
        // More Id's (add)
        int newIds = userNumber - _blockchain.id.ids.length;
        for (int i = 0; i < newIds; i++) _blockchain.id.ids.add(Uuid().v4());
      } else if (userNumber < _blockchain.id.ids.length) {
        // Less Id's (fresh list)
        _blockchain.id.ids = [];
        for (int i = 0; i < userNumber; i++)
          _blockchain.id.ids.add(Uuid().v4());
      }
      _blockchain.id.save();
    }
  }

  //Creates config file
  Future<void> saveConfig() async {
    Map<String, dynamic> configMap = {
      "Name": name,
      "Currency": currency,
      "Show Farmed ${_blockchain.currencySymbol.toUpperCase()}": showBalance,
      "Show Wallet Balance": showWalletBalance,
      "Show Hardware Info": showHardwareInfo,
      "Block Notifications": sendBalanceNotifications,
      "Plot Notifications": sendPlotNotifications,
      "Hard Drive Notifications": sendDriveNotifications,
      "Offline Notifications": sendOfflineNotifications,
      "Farm Status Notifications": sendStatusNotifications,
      "Parse Logs": parseLogs,
      "Number of Discord Users": userNumber,
      "Public API": publicAPI,
      "Swar's Chia Plot Manager Path": swarPath
    };

    //hides chiaPath from config.json if not defined (null)
    if (chiaPath != '')
      configMap.putIfAbsent("${_blockchain.binaryName}Path", () => chiaPath);

    //hides ignoreDiskSpace from config.json if false (default)
    if (ignoreDiskSpace)
      configMap.putIfAbsent("Ignore Disk Space", () => ignoreDiskSpace);

    //hpool's config.yaml
    if (type == ClientType.HPool || hpoolConfigPath != "")
      configMap.putIfAbsent("HPool Directory", () => hpoolConfigPath);

    //hpool's cookie
    if (type == ClientType.HPool || hpoolAuthToken != "")
      configMap.putIfAbsent("HPool Auth Token", () => hpoolAuthToken);

    //poolPublicKey used in FoxyPool's chia-og
    if (type == ClientType.FoxyPoolOG || poolPublicKey != "")
      configMap.putIfAbsent("Pool Public Key", () => poolPublicKey);

    var encoder = new JsonEncoder.withIndent("    ");
    String contents = encoder.convert([configMap]);

    _config.writeAsStringSync(contents);
  }

  Future<void> _askForBinPath() async {
    String exampleDir = (io.Platform.isLinux || io.Platform.isMacOS)
        ? "/home/user/${_blockchain.binaryName}-blockchain"
        : (io.Platform.isWindows)
            ? "C:\\Users\\user\\AppData\\Local\\${_blockchain.binaryName}-blockchain or C:\\Users\\user\\AppData\\Local\\${_blockchain.binaryName}-blockchain\\app-1.0.3\\resources\\app.asar.unpacked"
            : "";

    bool validDirectory = false;

    validDirectory = await _tryDirectories();

    if (validDirectory)
      log.info(
          "Automatically found ${_blockchain.binaryName} binary at: '${cache.binPath}'");
    else
      log.info("Could not automatically locate chia binary.");

    while (!validDirectory) {
      log.warning(
          "Specify your ${_blockchain.binaryName}-blockchain directory below: (e.g.: " +
              exampleDir +
              ")");

      _chiaPath = io.stdin.readLineSync() ?? '';
      log.info("Input chia path: '$_chiaPath'");

      cache.binPath = (io.Platform.isLinux || io.Platform.isMacOS)
          ? _chiaPath + "/venv/bin/${_blockchain.binaryName}"
          : _chiaPath + "\\daemon\\${_blockchain.binaryName}.exe";

      if (io.File(cache.binPath).existsSync())
        validDirectory = true;
      else if (io.Directory(chiaPath).existsSync())
        log.warning("""Could not locate chia binary in your directory.
(${cache.binPath} not found)
Please try again.
Make sure this folder has the same structure as Chia's GitHub repo.""");
      else
        log.warning(
            "Uh oh, that directory could not be found! Please try again.");
    }

    await saveConfig(); //saves path input by user to config
    cache.save(); //saves bin path to cache
  }

  //If in windows, tries a bunch of directories
  Future<bool> _tryDirectories() async {
    bool valid = false;

    late io.Directory chiaRootDir;
    late String file;

    if (io.Platform.isWindows) {
      //Checks if binary exist in C:\User\AppData\Local\chia-blockchain\resources\app.asar.unpacked\daemon\chia.exe
      chiaRootDir = io.Directory(io.Platform.environment['UserProfile']! +
          "/AppData/Local/${_blockchain.binaryName}-blockchain");

      file =
          "/resources/app.asar.unpacked/daemon/${_blockchain.binaryName}.exe";

      if (chiaRootDir.existsSync()) {
        await chiaRootDir.list(recursive: false).forEach((dir) {
          io.File trypath = io.File(dir.path + file);
          if (trypath.existsSync()) {
            cache.binPath = trypath.path;
            valid = true;
          }
        });
      }
    } else if (io.Platform.isLinux || io.Platform.isMacOS) {
      List<String> possiblePaths = [];

      if (io.Platform.isLinux) {
        chiaRootDir =
            io.Directory("/usr/lib/${_blockchain.binaryName}-blockchain");
        file = "/resources/app.asar.unpacked/daemon/${_blockchain.binaryName}";
      } else if (io.Platform.isMacOS) {
        chiaRootDir = io.Directory("/Applications/Chia.app/Contents");
        file = "/Resources/app.asar.unpacked/daemon/${_blockchain.binaryName}";
      }

      possiblePaths = [
        // checks if binary exists in /package:farmr_client/chia-blockchain/resources/app.asar.unpacked/daemon/chia in linux or
        // checks if binary exists in /Applications/Chia.app/Contents/Resources/app.asar.unpacked/daemon/chia in macOS
        chiaRootDir.path + file,
        // Checks if binary exists in /usr/package:farmr_client/chia-blockchain/resources/app.asar.unpacked/daemon/chia
        "/usr" + chiaRootDir.path + file,
        //checks if binary exists in /home/user/.local/bin/chia
        io.Platform.environment['HOME']! +
            "/.local/bin/${_blockchain.binaryName}"
      ];

      for (int i = 0; i < possiblePaths.length; i++) {
        io.File possibleFile = io.File(possiblePaths[i]);

        if (possibleFile.existsSync()) {
          cache.binPath = possibleFile.path;
          valid = true;
        }
      }
    }

    return valid;
  }

  Future<void> _loadConfig() async {
    var contents;

    try {
      contents = jsonDecode(_config.readAsStringSync());
    } catch (e) {
      //in json you need to use \\ for windows paths and this will ensure every \ is replaced with \\
      contents =
          jsonDecode(_config.readAsStringSync().replaceAll("\\", "\\\\"));
    }

    //leave this here for compatibility with old versions,
    //old versions stored id in config file
    if (contents[0]['id'] != null) _blockchain.id.ids.add(contents[0]['id']);

    //loads custom client name
    if (contents[0]['name'] != null) _name = contents[0]['name']; //old
    if (contents[0]['Name'] != null &&
        contents[0]['Name'] != "Farmer" &&
        contents[0]['Name'] != "Harvester" &&
        contents[0]['Name'] != "HPool" &&
        contents[0]['Name'] != "FoxyPool") _name = contents[0]['Name']; //new

    //loads custom currency
    if (contents[0]['currency'] != null)
      _currency = contents[0]['currency']; //old
    if (contents[0]['Currency'] != null)
      _currency = contents[0]['Currency']; //new

    _chiaPath = contents[0]['${_blockchain.binaryName}Path'] ?? "";

    //this used to be in the config file in earlier versions
    //do not remove this
    if (contents[0]['binPath'] != null) cache.binPath = contents[0]['binPath'];

    if (contents[0]['showBalance'] != null)
      _showBalance = contents[0]['showBalance']; //old
    if (contents[0]
            ['Show Farmed ${_blockchain.currencySymbol.toUpperCase()}'] !=
        null)
      _showBalance = contents[0]
          ['Show Farmed ${_blockchain.currencySymbol.toUpperCase()}']; //new

    if (contents[0]['showWalletBalance'] != null)
      _showWalletBalance = contents[0]['showWalletBalance']; //old
    if (contents[0]['Show Wallet Balance'] != null)
      _showWalletBalance = contents[0]['Show Wallet Balance']; //new

    if (contents[0]['sendPlotNotifications'] != null)
      _sendPlotNotifications = contents[0]['sendPlotNotifications']; //old
    if (contents[0]['Plot Notifications'] != null)
      _sendPlotNotifications = contents[0]['Plot Notifications']; //new

    if (contents[0]['sendBalanceNotifications'] != null)
      _sendBalanceNotifications = contents[0]['sendBalanceNotifications']; //old
    if (contents[0]['Block Notifications'] != null)
      _sendBalanceNotifications = contents[0]['Block Notifications']; //new

    if (contents[0]['sendOfflineNotifications'] != null)
      _sendOfflineNotifications = contents[0]['sendOfflineNotifications']; //old
    if (contents[0]['Offline Notifications'] != null)
      _sendOfflineNotifications = contents[0]['Offline Notifications']; //new

    if (contents[0]['sendStatusNotifications'] != null)
      _sendStatusNotifications = contents[0]['sendStatusNotifications']; //old
    if (contents[0]['Farm Status Notifications'] != null)
      _sendStatusNotifications = contents[0]['Farm Status Notifications']; //new

    if (contents[0]['parseLogs'] != null)
      _parseLogs = contents[0]['parseLogs']; //old
    if (contents[0]['Parse Logs'] != null)
      _parseLogs = contents[0]['Parse Logs']; //new

    if (contents[0]['Number of Discord Users'] != null)
      _userNumber = contents[0]['Number of Discord Users'];

    if (contents[0]["Swar's Chia Plot Manager Path"] != null)
      _swarPath = contents[0]["Swar's Chia Plot Manager Path"];

    if (contents[0]["Public API"] != null)
      _publicAPI = contents[0]["Public API"];

    if (contents[0]["Ignore Disk Space"] != null)
      _ignoreDiskSpace = contents[0]["Ignore Disk Space"];

    if (contents[0]['Hard Drive Notifications'] != null)
      _sendDriveNotifications = contents[0]['Hard Drive Notifications']; //new

    if (contents[0]['HPool Directory'] != null)
      _hpoolConfigPath = contents[0]['HPool Directory']; //new

    if (contents[0]['HPool Auth Token'] != null)
      _hpoolAuthToken = contents[0]['HPool Auth Token']; //new

    //loads pool public key used by foxypool mode
    if (contents[0]['Pool Public Key'] != null) {
      _poolPublicKey = contents[0]['Pool Public Key'];

      //appends 0x to pool public key if it doesnt start with 0x
      if (_poolPublicKey.length == 96 && !_poolPublicKey.startsWith("0x"))
        _poolPublicKey = "0x" + poolPublicKey;
    }

    if (contents[0]["Show Hardware Info"] != null)
      _showHardwareInfo = contents[0]["Show Hardware Info"];

    await saveConfig();
  }

  /*void _showQR(Console console) {
    final qrCode = new QrCode(3, QrErrorCorrectLevel.L);
    qrCode.addData(cache.ids[0]);
    qrCode.make();

    for (int x = 0; x < qrCode.moduleCount; x++) {
      for (int y = 0; y < qrCode.moduleCount; y++) {
        if (qrCode.isDark(y, x)) {
          console.setBackgroundColor(ConsoleColor.black);
          console.setForegroundColor(ConsoleColor.white);
          console.write("  ");
        } else {
          console.setBackgroundColor(ConsoleColor.white);
          console.setForegroundColor(ConsoleColor.black);
          console.write("  ");
        }
      }
      console.resetColorAttributes();
      console.write("\n");
    }
  }*/
}

//Tells if client is harvester or not
enum ClientType { Farmer, Harvester, HPool, FoxyPoolOG }
