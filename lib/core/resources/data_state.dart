abstract class DataState<T> {
  final String? error;
  final T? data;

  DataState(this.data, this.error);
}

class DataFailed<T> extends DataState<T> {
  DataFailed(error) : super(null, error);
}

class DataSuccess<T> extends DataState<T> {
  DataSuccess(data) : super(data, null);
}
