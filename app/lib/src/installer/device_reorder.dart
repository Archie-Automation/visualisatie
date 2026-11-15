/// Zet het item van [from] op de plek [to], beide indexen vóór het verwijderen.
/// Het gesleepte item neemt die rij over; de rest schuift op.
/// Geeft de nieuwe index terug, of null als er niets verandert.
int? placeListItem<T>(List<T> list, int from, int to) {
  if (from == to) return null;
  if (from < 0 || to < 0 || from >= list.length || to >= list.length) {
    return null;
  }
  final item = list.removeAt(from);
  list.insert(to, item);
  return to;
}
