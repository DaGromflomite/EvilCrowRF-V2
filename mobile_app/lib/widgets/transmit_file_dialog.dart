import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/ble_provider.dart';
import '../providers/notification_provider.dart';
import '../theme/app_colors.dart';

/// Widget for confirming and transmitting signal from file
class TransmitFileDialog {
  static const String _dontShowAgainKey = 'transmit_file_dialog_dont_show_again';
  
  /// Checks if confirmation dialog should be shown
  static Future<bool> shouldShowDialog() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_dontShowAgainKey) ?? false);
  }
  
  /// Resets the "don't show again" setting
  static Future<void> resetDontShowAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dontShowAgainKey);
  }
  
  /// Shows confirmation dialog and transmits signal
  /// 
  /// [context] - context for showing dialog
  /// [fileName] - filename for display
  /// [filePath] - file path for transmission
  /// [pathType] - path type (0=RECORDS, 1=SIGNALS, 2=PRESETS, 3=TEMP)
  /// 
  /// Returns true if transmission started successfully, false if cancelled
  static Future<bool> showAndTransmit(
    BuildContext context, {
    required String fileName,
    required String filePath,
    int pathType = 0,
  }) async {
    final bleProvider = Provider.of<BleProvider>(context, listen: false);
    
    if (!bleProvider.isConnected) {
      final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
      notificationProvider.showError(AppLocalizations.of(context)!.notConnectedToDevice);
      return false;
    }
    
    // Check if dialog needs to be shown
    final shouldShow = await shouldShowDialog();
    if (!shouldShow) {
      // Skip dialog and transmit immediately
      try {
        await bleProvider.transmitFromFile(filePath, pathType: pathType);
        if (context.mounted) {
          final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
          notificationProvider.showSuccess(AppLocalizations.of(context)!.signalTransmissionStarted(fileName));
        }
        return true;
      } catch (e) {
        if (context.mounted) {
          final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
          notificationProvider.showError(AppLocalizations.of(context)!.transmissionError(e.toString()));
        }
        return false;
      }
    }
    
    // Show confirmation dialog with a large tap/hold transmit button.
    bool dontShowAgain = false;
    bool transmitting = false;

    Future<void> savePref() async {
      if (dontShowAgain) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_dontShowAgainKey, true);
      }
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.transmitSignal,
                      style: const TextStyle(color: AppColors.primaryText),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.transmitSignalConfirm,
                    style: const TextStyle(color: AppColors.primaryText),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${AppLocalizations.of(context)!.file}: $fileName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.transmitWarning,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Large, finger-friendly transmit toggle: tap once to start
                  // transmitting continuously, tap again to stop. Clearer than
                  // press-and-hold on a touchscreen (no accidental release).
                  GestureDetector(
                    onTap: () async {
                      if (transmitting) {
                        // Stop
                        bleProvider.stopRepeatTransmit();
                        setState(() => transmitting = false);
                      } else {
                        // Start continuous transmission
                        await savePref();
                        setState(() => transmitting = true);
                        bleProvider.startRepeatTransmit(filePath,
                            pathType: pathType);
                        if (context.mounted) {
                          Provider.of<NotificationProvider>(context,
                                  listen: false)
                              .showSuccess(AppLocalizations.of(context)!
                                  .signalTransmissionStarted(fileName));
                        }
                      }
                    },
                    child: Container(
                      height: 72,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: transmitting
                            ? AppColors.error
                            : AppColors.warning,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              transmitting
                                  ? Icons.stop_circle
                                  : Icons.send,
                              color: AppColors.primaryBackground,
                              size: 28),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              transmitting
                                  ? '● TRANSMITTING — TAP TO STOP'
                                  : 'TAP TO TRANSMIT',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.primaryBackground,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() {
                        dontShowAgain = value ?? false;
                      });
                    },
                    title: Text(
                      AppLocalizations.of(context)!.dontShowAgain,
                      style: const TextStyle(color: AppColors.primaryText),
                    ),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primaryAccent,
                    checkColor: AppColors.primaryBackground,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    bleProvider.stopRepeatTransmit();
                    Navigator.of(context).pop(false);
                  },
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
              ],
            );
          },
        );
      },
    );

    // Safety: ensure repeat is stopped if the dialog closed unexpectedly.
    bleProvider.stopRepeatTransmit();
    return result == true;
  }
}

