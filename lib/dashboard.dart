import 'package:carbine/lib.dart';
import 'package:carbine/main.dart';
import 'package:carbine/number_pad.dart';
import 'package:carbine/scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';

class Dashboard extends StatefulWidget {
  final FederationSelector fed;

  const Dashboard({super.key, required this.fed});

  @override
  State<Dashboard> createState() => _DashboardState();
}

enum PaymentType { lightning, onchain, ecash }

class _DashboardState extends State<Dashboard> {
  BigInt? balanceMsats;
  bool isLoadingBalance = true;
  bool isLoadingTransactions = true;
  final List<Transaction> _transactions = [];
  bool showMsats = false;

  Transaction? _lastTransaction;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  PaymentType _selectedPaymentType = PaymentType.lightning;

  VoidCallback? _pendingAction;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadBalance();
    _loadTransactions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleAction(VoidCallback action) {
    setState(() {
      _pendingAction = action;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100 &&
      !_isFetchingMore &&
      _hasMore) {
      _loadTransactions(loadMore: true);
    }
  }

  Future<void> _loadBalance() async {
    final bal = await balance(federationId: widget.fed.federationId);
    setState(() {
      balanceMsats = bal;
      isLoadingBalance = false;
    });
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    if (_isFetchingMore) return;
    _isFetchingMore = true;

    if (!loadMore) {
      setState(() {
        isLoadingTransactions = true;
        _transactions.clear();
        _hasMore = true;
        _lastTransaction = null;
      });
    }

    final newTxs = await transactions(
      federationId: widget.fed.federationId,
      timestamp: loadMore ? _lastTransaction?.timestamp : null,
      operationId: loadMore ? _lastTransaction?.operationId : null,
    );

    setState(() {
      _transactions.addAll(newTxs);
      if (newTxs.length < 10) {
        _hasMore = false;
      }
      if (newTxs.isNotEmpty) {
        _lastTransaction = newTxs.last;
      }
      isLoadingTransactions = false;
      _isFetchingMore = false;
    });
  }

  void _onSendPressed() async {
    if (_selectedPaymentType == PaymentType.lightning) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanQRPage(selectedFed: widget.fed)));
    } else if (_selectedPaymentType == PaymentType.ecash) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => NumberPad(fed: widget.fed, paymentType: _selectedPaymentType)));
    }
    _loadBalance();
    _loadTransactions();
  }

  void _onReceivePressed() async {
    if (_selectedPaymentType == PaymentType.lightning) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => NumberPad(fed: widget.fed, paymentType: _selectedPaymentType)));
    } else if (_selectedPaymentType == PaymentType.ecash) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanQRPage(selectedFed: widget.fed)));
    }

    _loadBalance();
    _loadTransactions();
  } 

    @override
  Widget build(BuildContext context) {
    final name = widget.fed.federationName;

    return Scaffold(
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onClose: () async {
          if (_pendingAction != null) {
            await Future.delayed(const Duration(milliseconds: 200));
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _pendingAction!();
              _pendingAction = null;
            });
          }
        },
        children: [
          SpeedDialChild(
            child: const Icon(Icons.download),
            label: 'Receive',
            backgroundColor: Colors.green,
            onTap: () => _scheduleAction(_onReceivePressed),
          ),
          SpeedDialChild(
            child: const Icon(Icons.upload),
            label: 'Send',
            backgroundColor: Colors.blue,
            onTap: () => _scheduleAction(_onSendPressed),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
              child: Text(
                name.toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 10,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),
            if (isLoadingBalance)
              const CircularProgressIndicator()
            else
              GestureDetector(
                onTap: () {
                  setState(() {
                    showMsats = !showMsats;
                  });
                },
                child: Text(
                  formatBalance(balanceMsats, showMsats),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 48),
            SegmentedButton<PaymentType>(
              segments: const [
                ButtonSegment(
                  value: PaymentType.lightning,
                  label: Text('Lightning'),
                  icon: Icon(Icons.flash_on),
                ),
                ButtonSegment(
                  value: PaymentType.onchain,
                  label: Text('Onchain'),
                  icon: Icon(Icons.link),
                ),
                ButtonSegment(
                  value: PaymentType.ecash,
                  label: Text('Ecash'),
                  icon: Icon(Icons.currency_bitcoin),
                ),
              ],
              selected: {_selectedPaymentType},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _selectedPaymentType = newSelection.first;
                });
              },
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 20, horizontal: 24)),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                ),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.primary;
                  }
                  return Theme.of(context).colorScheme.surfaceContainerHighest;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return Colors.black87;
                }),
                side: WidgetStateProperty.all(const BorderSide(color: Colors.transparent)),
                shadowColor: WidgetStateProperty.all(Colors.black.withOpacity(0.2)),
                elevation: WidgetStateProperty.resolveWith<double>((states) {
                  return states.contains(WidgetState.selected) ? 6 : 0;
                }),
              ),
            ),
            const SizedBox(height: 48),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Recent Transactions",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            isLoadingTransactions
                ? const CircularProgressIndicator()
                : _transactions.isEmpty
                    ? const Text('No transactions yet')
                    : SizedBox(
                        height: 300,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _transactions.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _transactions.length) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            final tx = _transactions[index];
                            final isIncoming = tx.received;
                            final date = DateTime.fromMillisecondsSinceEpoch(tx.timestamp.toInt());
                            final formattedDate = DateFormat.yMMMd().add_jm().format(date);
                            final formattedAmount = formatBalance(tx.amount, false);

                            IconData moduleIcon;
                            switch (tx.module) {
                              case 'ln':
                              case 'lnv2':
                                moduleIcon = Icons.flash_on;
                                break;
                              case 'wallet':
                                moduleIcon = Icons.link;
                                break;
                              case 'mint':
                                moduleIcon = Icons.currency_bitcoin;
                                break;
                              default:
                                moduleIcon = Icons.help_outline;
                            }

                            final amountStyle = TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isIncoming ? Colors.green : Colors.red,
                            );

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isIncoming ? Colors.green.shade50 : Colors.red.shade50,
                                  child: Icon(
                                    moduleIcon,
                                    color: isIncoming ? Colors.green : Colors.red,
                                  ),
                                ),
                                title: Text(isIncoming ? "Received" : "Sent"),
                                subtitle: Text(formattedDate),
                                trailing: Text(formattedAmount, style: amountStyle),
                              ),
                            );
                          },
                        ),
                      ),
          ],
        ),
      ),
    );
  }
}


