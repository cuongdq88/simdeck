import 'package:nocterm/nocterm.dart';

class SimutilApp extends StatefulComponent {
  const SimutilApp({super.key});

  @override
  State<SimutilApp> createState() => _SimutilAppState();
}

class _SimutilAppState extends State<SimutilApp> {
  String focusKey = "android";

  Future<void> parseAbd

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Focusable(
                    focused: focusKey == "android",
                    onKeyEvent: (event) {
                      if (event.logicalKey == LogicalKey.arrowDown) {
                        setState(() {
                          focusKey = "ios";
                        });
                        return true;
                      }
                      return false;
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: BoxBorder.all(
                          width: 1.5,
                          style: BoxBorderStyle.rounded,
                          color: focusKey == "android"
                              ? Colors.green
                              : Colors.gray,
                        ),
                        title: BorderTitle(text: 'Android'),
                      ),
                      child: ListView.builder(
                        itemCount: 10,
                        itemBuilder: (context, index) {
                          return Text('Android $index');
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Focusable(
                    focused: focusKey == "ios",
                    onKeyEvent: (event) {
                      if (event.logicalKey == LogicalKey.arrowUp) {
                        setState(() {
                          focusKey = "android";
                        });
                        return true;
                      }
                      return false;
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: BoxBorder.all(
                          width: 1.5,
                          style: BoxBorderStyle.rounded,
                          color: focusKey == "ios" ? Colors.green : Colors.gray,
                        ),
                        title: BorderTitle(text: 'iOS'),
                      ),
                      child: Center(child: Text('Content here')),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.rounded),
                title: BorderTitle(text: 'Logcat'),
              ),
              child: Center(child: Text('Content here')),
            ),
          ),
        ],
      ),
    );
  }
}
