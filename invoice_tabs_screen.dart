import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common/custom_appbar.dart';
import '../../common/custom_color.dart';
import '../../common/responsive_builder.dart';
import '../../controllers/estimates_controller.dart';
import '../../controllers/invoice_controller.dart';
import '../../controllers/theme_controller.dart';
import 'manage_invoice_details_screen.dart';
import 'preview_invoice_screen.dart';

class InvoiceTabsScreen extends StatefulWidget {
  final bool isEstimate;
  final bool isEdit;
  const InvoiceTabsScreen({
    super.key,
    required this.isEstimate,
    required this.isEdit,
  });

  @override
  State<InvoiceTabsScreen> createState() => _InvoiceTabsScreenState();
}

class _InvoiceTabsScreenState extends State<InvoiceTabsScreen>
    with SingleTickerProviderStateMixin {
  ThemeController themeController = Get.find();
  InvoiceController invoiceController = Get.put(InvoiceController());
  EstimatesController estimatesController = Get.put(EstimatesController());
  late TabController _tabController;
  int currentTabIndex = 0;
  bool isEdit = true;
  @override
  void initState() {
    isEdit = widget.isEdit;
    _tabController = TabController(
      length: 2,
      vsync: this,
    );
    _tabController.addListener(() {
      setState(() {
        currentTabIndex = _tabController.index;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    invoiceController.clearData();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: customAppBar(
        title: currentTabIndex == 0 ? "Invoice" : "Preview",
        context: context,
        isBack: true,
        mapBack: true,
        function: () {
          if (currentTabIndex == 1) {
            _tabController.animateTo(0);
          } else {
            Get.back();
          }
        },
      ),
      backgroundColor: (themeController.isDarkMode.value)
          ? CustomColor.themeColor.value
          : CustomColor.lightGray.value,
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ResponsiveBuilder.isMobile(context) ? Get.width : 1000,
          ),
          child: Column(
            children: [
              IgnorePointer(
                child: TabBar(
                  controller: _tabController,
                  // indicatorPadding: EdgeInsets.symmetric(horizontal: 10.w),
                  indicatorSize: TabBarIndicatorSize.label,
                  unselectedLabelColor: CustomColor.darkGray.value,
                  labelColor: CustomColor.bgColor.value,
                  indicatorColor: CustomColor.bgColor.value,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(
                      text: "Invoice",
                    ),
                    Tab(
                      text: "Preview",
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  controller: _tabController,
                  children: [
                    ManageInvoiceDetailsScreen(
                      isEstimate: widget.isEstimate,
                      isEdit: isEdit,
                      onSave: () => _tabController.animateTo(1),
                    ),
                    PreviewInvoiceScreen(
                      onBack: () {
                        if (!isEdit) {
                          setState(() {
                            isEdit = true;
                          });
                          if (widget.isEstimate) {
                            invoiceController.setInvoiceDataForEditEstimate(
                              invoiceId: invoiceController
                                  .currentInvoiceModel.value.docId,
                              estimateModel:
                                  invoiceController.currentInvoiceEstimateModel,
                            );
                          } else {
                            invoiceController.setInvoiceDataForEdit(
                              invModel:
                                  invoiceController.currentInvoiceModel.value,
                              customerModel:
                                  invoiceController.currentCustomerModel.value,
                            );
                          }
                        }
                        _tabController.animateTo(0);
                      },
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
