// Backward-compatible alias for older MVP code paths.
class MockAlertProvider extends MockAlertSource {
    function initialize() {
        MockAlertSource.initialize();
    }
}
