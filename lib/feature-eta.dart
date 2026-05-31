import 'dart:math';

// ==========================================
//         LÓGICA DEL BACKEND (ETA)
//         Desarrollado por: Gabriel
// ==========================================

// Coordenadas fijas de las paradas
const double PARADA_CALIFORNIA_LAT = 10.483376;
const double PARADA_CALIFORNIA_LNG = -66.819402;
const double PARADA_UNIVERSIDAD_LAT = 10.491676;
const double PARADA_UNIVERSIDAD_LNG = -66.779953;

// Velocidad promedio de la camioneta en km/h
const double VELOCIDAD_PROMEDIO = 40.0;

// ==========================================
//    FÓRMULA DE HAVERSINE
//    Calcula la distancia entre dos puntos
//    en la superficie de la Tierra (en km)
// ==========================================
double calcularDistanciaKm(double lat1, double lng1, double lat2, double lng2) {
  const double radioTierra = 6371.0; // Radio de la Tierra en km

  // Convertir grados a radianes
  double dLat = gradosARadianes(lat2 - lat1);
  double dLng = gradosARadianes(lng2 - lng1);

  // Fórmula de Haversine
  double a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(gradosARadianes(lat1)) *
          cos(gradosARadianes(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);

  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return radioTierra * c;
}

double gradosARadianes(double grados) {
  return grados * (pi / 180);
}

// ==========================================
//    CALCULAR ETA
//    Recibe la posición actual de la camioneta
//    y devuelve los minutos a cada parada
// ==========================================
Map<String, dynamic> calcularETA(double latCamioneta, double lngCamioneta) {
  // Distancia a cada parada en km
  double distanciaCalifornia = calcularDistanciaKm(
    latCamioneta,
    lngCamioneta,
    PARADA_CALIFORNIA_LAT,
    PARADA_CALIFORNIA_LNG,
  );

  double distanciaUniversidad = calcularDistanciaKm(
    latCamioneta,
    lngCamioneta,
    PARADA_UNIVERSIDAD_LAT,
    PARADA_UNIVERSIDAD_LNG,
  );

  // ETA en minutos = (distancia / velocidad) * 60
  double etaCalifornia = (distanciaCalifornia / VELOCIDAD_PROMEDIO) * 60;
  double etaUniversidad = (distanciaUniversidad / VELOCIDAD_PROMEDIO) * 60;

  return {
    'parada_california': {
      'distancia_km': distanciaCalifornia.toStringAsFixed(2),
      'eta_minutos': etaCalifornia.toStringAsFixed(1),
    },
    'parada_universidad': {
      'distancia_km': distanciaUniversidad.toStringAsFixed(2),
      'eta_minutos': etaUniversidad.toStringAsFixed(1),
    },
  };
}
