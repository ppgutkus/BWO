import 'dart:math';

import 'package:http/http.dart' as http;

import '../../entity/player/player.dart';
import '../../entity/wall/foundation.dart';
import '../../map/ground.dart';
import '../../map/map_controller.dart';
import '../../map/tree.dart';
import '../../server/utils/server_utils.dart';
import '../../utils/tap_state.dart';
import '../../utils/timer_helper.dart';
import '../../utils/toast_message.dart';

class BuildFoundation {
  final Player _player;
  final MapController _map;

  List<Foundation> foundationList = [];
  Foundation myFoundation;

  BuildFoundation(this._player, this._map);

  void createFoundation(dynamic foundationData, Function(bool) callback) {
    var x = double.parse(foundationData['x'].toString());
    var y = double.parse(foundationData['y'].toString());
    var w = double.parse(foundationData['w'].toString());
    var h = double.parse(foundationData['h'].toString());

    var newArea = Rectangle(x, y, w, h);
    var initialArea = Rectangle(-16, -16, 32, 32);

    if (isInsideSpecialArea(newArea, initialArea)) {
      Toast.add("You can't place foundations inside initial area.");
      callback(false);
      return;
    }

    //checks if there are any other too close or inside, if not proceed
    getAllFoundationAround(x.floor(), y.floor(), w.toInt(), h.toInt())
        .then((isAvailable) {
      if (isAvailable.body == 'true') {
        var isValid = checkIfTerrainLocationIsValid(
            x.floor(), y.floor(), w.toInt(), h.toInt());
        if (!isValid) return;

        instantiateFoundation(foundationData);
        callback(true);
      } else {
        Toast.add('This area is now available to place your foundation');
      }
    });
  }

  bool checkIfTerrainLocationIsValid(int x, int y, int w, int h) {
    var trees = getAmountOfTreesAround(x, y, w, h);

    if (trees.length > 0) {
      Toast.add("This place if blocked by a Tree. You should remove it first.");
      return false;
    }

    if (isAboveWater(x, y, w, h)) {
      Toast.add("You can't place foundations above water");
      return false;
    }

    var newArea = Rectangle(x, y, w, h);
    var initialArea = Rectangle(-16, -16, 32, 32);
    if (isInsideSpecialArea(newArea, initialArea)) {
      Toast.add("You can't place foundations inside initial aera.");
      return false;
    }
    return true;
  }

  Future<http.Response> getAllFoundationAround(int x, int y, int w, int h) {
    print('requesting foundation location avaiablity');
    return http.get('${ServerUtils.server}/foundations/at/$x/$y/$w/$h');
  }

  bool isInsideSpecialArea(Rectangle r1, Rectangle r2) {
    return r1.intersects(r2);
  }

  List<dynamic> getAmountOfTreesAround(int left, int top, int w, int h) {
    var treeList = [];
    for (var entity in _map.entitysOnViewport) {
      if (entity is Tree) {
        if (entity.posX >= left &&
            entity.posY >= top &&
            entity.posX <= left + w &&
            entity.posY <= top + h) {
          treeList.add(entity);
        }
      }
    }

    return treeList;
  }

  bool isAboveWater(int left, int top, int w, int h) {
    var right = left + w;
    var bottom = top + h;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (_map.map[y][x][0].height < Ground.lowWater) {
          return true;
        }
      }
    }
    return false;
  }

  void updateOrInstantiateFoundation(dynamic foundationData) {
    var foundationExists = checkIfFoundationExists(foundationData);

    if (foundationExists != null) {
      updateBounds(foundationExists, foundationData);
      replaceWalls(foundationExists, foundationData['walls']);
      replaceFloors(foundationExists, foundationData['floors']);
    } else {
      instantiateFoundation(foundationData);
    }
  }

  void instantiateFoundation(dynamic foundationData) {
    var tmpFoundation = Foundation(foundationData, _map, _player);
    if (myFoundation == null) {
      if (foundationData['owner'] == _player.name) {
        myFoundation = tmpFoundation;
      }
    }
    foundationList.add(tmpFoundation);
    replaceWalls(tmpFoundation, foundationData['walls']);
    replaceFloors(tmpFoundation, foundationData['floors']);
  }

  void placeWall(int selectedWall) {
    if (myFoundation == null) return;
    var tap = TapState.screenToWorldPoint(TapState.currentPosition, _map) / 16;
    myFoundation.addWall(tap.dx, tap.dy, selectedWall);
  }

  void deleteWall() {
    if (myFoundation == null) return;

    var tap = TapState.screenToWorldPoint(TapState.currentPosition, _map) / 16;
    myFoundation.deleteWall(tap.dx, tap.dy);
  }

  Foundation checkIfFoundationExists(dynamic foundationData) {
    for (var item in foundationList) {
      if (foundationData['owner'] == item.foundationData['owner']) {
        return item;
      }
    }
    return null;
  }

  void updateBounds(Foundation currentFoundation, dynamic newData) {
    if (currentFoundation == null) return;
    var t = TimerHelper();
    var x = currentFoundation.foundationData['x'];
    var y = currentFoundation.foundationData['y'];
    var w = currentFoundation.foundationData['w'];
    var h = currentFoundation.foundationData['h'];
    if (x != newData['x'] ||
        y != newData['y'] ||
        w != newData['w'] ||
        h != newData['h']) {
      currentFoundation.setup(newData);
    }
    t.logDelayPassed('updateBounds:');
  }

  void replaceWalls(Foundation currentFoundation, dynamic newWalls) async {
    if (currentFoundation == null) return;
    var t = TimerHelper();

    currentFoundation.wallList.forEach((key, wall) {
      wall.destroy();
    });

    for (var wall in newWalls) {
      var x = wall['x'].toDouble();
      var y = wall['y'].toDouble();
      var id = wall['id'];

      currentFoundation.addWall(x, y, id);
    }
    //print(currentFoundation.wallList);

    // for (var wall in newWalls) {
    //   var objId = '_${wall['x']}_${wall['y']}';
    //   var wallAlreadyOnMap = currentFoundation.wallList[objId];

    //   if (wallAlreadyOnMap != null) {
    //     wallAlreadyOnMap.updateWith(wall);
    //   } else {
    //     wall.destroy();
    //   }
    // }
    t.logDelayPassed('replaceWalls:');
  }

  // ------------------ floors -------------------------------
  void placeFloor(int selectedFloor) {
    if (myFoundation == null) return;
    var tap = TapState.screenToWorldPoint(TapState.currentPosition, _map) / 16;
    myFoundation.addFloor(tap.dx, tap.dy, selectedFloor);
  }

  void replaceFloors(Foundation currentFoundation, dynamic newFloors) {
    if (currentFoundation == null) return;

    currentFoundation.tileList.forEach((key, tile) {
      tile = null;
    });

    for (var tile in newFloors) {
      var x = double.parse(tile['x'].toString());
      var y = double.parse(tile['y'].toString());
      var id = int.parse(tile['id'].toString());

      currentFoundation.addFloor(x, y, id);
    }
  }
}