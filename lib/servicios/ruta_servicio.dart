import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart'; // O el paquete de mapas que uses

class RutaServicio {
  Future<List<LatLng>> obtenerRuta(LatLng origen, LatLng destino) async {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${origen.longitude},${origen.latitude};${destino.longitude},${destino.latitude}?overview=full&geometries=geojson');
    
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> coordinates = data['routes'][0]['geometry']['coordinates'];
      return coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
    } else {
      throw Exception('Error al cargar la ruta');
    }
  }
}