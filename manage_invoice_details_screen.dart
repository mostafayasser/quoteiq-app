import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../common/assets_utility.dart';
import '../../common/constant.dart';
import '../../common/container_shadow.dart';
import '../../common/custom_button.dart';
import '../../common/custom_color.dart';
import '../../common/drop_down.dart';
import '../../common/loader.dart';
import '../../common/snackbar.dart';
import '../../common/text_field.dart';
import '../../common/text_style.dart';
import '../../controllers/company_profile_controller.dart';
import '../../controllers/email_templates_controller.dart';
import '../../controllers/invoice_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../helpers/validators.dart';
import '../../model/invoice_model.dart';
import '../../model/invoice_package_model.dart';
import '../../model/invoice_service_model.dart';
import '../../utils/custom_date_time_selector.dart';
import '../estimates/widgets/complete_bank_info_widget.dart';
import '../my_contacts/add_customer.dart';
import '../widgets/totals_section_widget.dart';
import 'widgets/add_invoice_custom_service_widget.dart';
import 'widgets/invoice_service_item_widget.dart';
import '../send_email/send_email_screen.dart';
import '../widgets/attachments_gallery_widget.dart';
import '../widgets/choose_customer_address.dart';
import '../widgets/drop_down_search_widget.dart';
import '../widgets/invoice_payment_methods_dialog.dart';
import '../widgets/invoice_payment_terms_dialog.dart';
import '../widgets/pick_image_sheet.dart';
import '../widgets/responsive_builder.dart';
import 'widgets/add_invoice_service_button.dart';

class ManageInvoiceDetailsScreen extends StatefulWidget {
  final bool isEstimate;
  final bool isEdit;
  final VoidCallback onSave;

  const ManageInvoiceDetailsScreen({
    required this.isEstimate,
    required this.isEdit,
    required this.onSave,
    super.key,
  });

  @override
  State<ManageInvoiceDetailsScreen> createState() =>
      _ManageInvoiceDetailsScreenState();
}

class _ManageInvoiceDetailsScreenState
    extends State<ManageInvoiceDetailsScreen> {
  final invoiceController = Get.put(InvoiceController());
  final companyProfileController = Get.find<CompanyProfileController>();
  final themeController = Get.find<ThemeController>();

  TextEditingController clientMessageController = TextEditingController();
  TextEditingController invoiceNoController = TextEditingController();

  String currencySymbol = "\$";
  DateFormat dateFormat = DateFormat("MM/dd/yyyy");

  bool taxEnabled = true;
  bool isPackageEstimate = false;
  bool showPrices = false;
  bool hasEditPermission = false;
  bool isRecurrenceStarted = false, isEditEnabled = true;
  RxString recurrenceType = "".obs;
  RxString recurrenceStartDate = "".obs;
  RxString recurrenceEndDate = "".obs;
  RxBool loading = true.obs;

  List<String> serviceTypes = [];

  setInvoiceDate(String date) {
    invoiceController.currentInvoiceModel.value.invoiceDate = date;
    invoiceController.currentInvoiceModel.refresh();
  }

  setInvoiceStatus(String status) {
    invoiceController.currentInvoiceModel.value.paymentStatus = status;
    invoiceController.currentInvoiceModel.refresh();
  }

  setInvoicePaymentTerm(String term) {
    invoiceController.currentInvoiceModel.value.paymentTerm = term;
    invoiceController.currentInvoiceModel.refresh();
  }

  setInvoiceTax() {
    if (!taxEnabled) {
      invoiceController.currentInvoiceModel.value.taxRatePer = 0;
    } else {
      double companyTax =
          companyProfileController.companyInfo.value.taxPercentage;
      invoiceController.currentInvoiceModel.value.taxRatePer =
          companyTax.toPrecision(2);
    }
    invoiceController.updateInvoiceTotals();
  }

  saveInvoice() async {
    var model = invoiceController.currentInvoiceModel.value;
    int invoiceNumber = int.tryParse(invoiceNoController.text) ?? 0;
    if (invoiceNumber < model.invoiceNumber) {
      ShowSnackBar.error(
        "Invoice number should be greater than or equal ${model.invoiceNumber}",
      );
      return;
    } else {
      invoiceController.currentInvoiceModel.value.invoiceNumber = invoiceNumber;
      model.invoiceNumber = invoiceNumber;
    }
    invoiceController.currentInvoiceModel.value.clientMessage =
        clientMessageController.text;
    model.clientMessage = clientMessageController.text;
    if (!widget.isEdit) {
      if (invoiceController.currentCustomerModel.value.docId.isEmpty) {
        ShowSnackBar.error("Please select a client");
        return;
      }
      if (model.serviceList.isEmpty && model.packagesList.isEmpty) {
        ShowSnackBar.error("Please add at least one item");
        return;
      }
    }
    debugPrint(model.toMap().toString());
    bool isEstimateInvoice =
        invoiceController.currentInvoiceModel.value.estimateId.isNotEmpty;
    if (invoiceController.currentInvoiceModel.value.isRecurring) {
      String errorMessage = invoiceController.isValidRecurrenceData(
        isRecurrenceStarted: isRecurrenceStarted,
        recurrenceStartDate: recurrenceStartDate.value,
        recurrenceEndDate: recurrenceEndDate.value,
        recurrenceType: recurrenceType.value,
      );
      if (errorMessage.isNotEmpty) {
        ShowSnackBar.error(errorMessage);
        return;
      }
      Loader.showLoader();
      errorMessage = await invoiceController.isValidStripeData();
      Loader.hideLoader();
      if (errorMessage.isNotEmpty) {
        ShowSnackBar.error(errorMessage);
        return;
      }
    }

    Loader.showLoader();
    if (!widget.isEdit && !widget.isEstimate) {
      await invoiceController.createInvoiceDoc();
    } else if (!widget.isEdit && widget.isEstimate) {
      invoiceController.currentInvoiceModel.value.docId =
          invoiceController.currentInvoiceEstimateModel.docId;
    }
    if (invoiceController.currentInvoiceModel.value.isRecurring) {
      await invoiceController.setInvoiceRecurrenceDataForSave(
        isRecurrenceStarted: isRecurrenceStarted,
        recurrenceType: recurrenceType.value,
        recurrenceStartDate: recurrenceStartDate.value,
        recurrenceEndDate: recurrenceEndDate.value,
      );
    } else {
      if (invoiceController
          .currentInvoiceModel.value.stripeScheduleSubscriptionId.isNotEmpty) {
        await invoiceController.checkForCancelingRecurringInvoice(
            isEditEnabled: isEditEnabled);
      }
    }
    await invoiceController.saveInvoiceData(
      isEdit: widget.isEdit,
      isEstimateInvoice: isEstimateInvoice,
    );
    Loader.hideLoader();
  }

  bool checkShowCancelRecurringOption() {
    var invoice = invoiceController.currentInvoiceModel.value;
    debugPrint("####${invoice.recurringInvoiceStartDateTimestamp}");
    if (widget.isEdit &&
        invoice.isRecurring &&
        invoice.recurrenceMainReferenceInvoiceDocId.isEmpty &&
        invoice.stripeScheduleSubscriptionId.isNotEmpty) {
      return true;
    }
    return false;
  }

  bool hasAddCustomerPermission() {
    List<String> customerScreenPermission = invoiceController.authController
        .checkScreenUserPermission(AppConstant.customersScreen);
    if (customerScreenPermission.contains(AppConstant.addCustomers)) {
      return true;
    } else {
      return false;
    }
  }

  setCustomerAddress(int index) {
    var addressesList =
        invoiceController.currentCustomerModel.value.customerAddressesList;
    for (var element in addressesList) {
      element.active = false;
    }
    invoiceController
        .currentCustomerModel.value.customerAddressesList[index].active = true;
    invoiceController.currentInvoiceModel.value.address =
        addressesList[index].formattedAddress;
    invoiceController.currentInvoiceModel.value.addressId =
        addressesList[index].placeId;
    invoiceController.currentInvoiceModel.refresh();
  }

  @override
  void initState() {
    double companyTax =
        companyProfileController.companyInfo.value.taxPercentage;
    var invoicePermissions = invoiceController.invoiceScreensUserPermissions;
    debugPrint("initState");
    currencySymbol = companyProfileController.currencySymbol.value;
    invoiceNoController.clear();
    clientMessageController.clear();
    if (!widget.isEdit && !widget.isEstimate) {
      invoiceController.setCreateInvoiceDefaultData();
    }
    var invoiceModel = invoiceController.currentInvoiceModel.value;
    invoiceNoController.text = invoiceModel.invoiceNumber.toString();
    clientMessageController.text = invoiceModel.clientMessage;

    if (widget.isEdit) {
      if (invoiceModel.stripeSubscriptionIntervalName.isNotEmpty) {
        recurrenceType.value = formatIntervalNameToRecurrenceTypeValue(
            invoiceModel.stripeSubscriptionIntervalName);
        if (recurrenceType.value == RecurrenceType.weekly.value &&
            invoiceModel.stripeSubscriptionIntervalCount == 2) {
          recurrenceType.value = RecurrenceType.biweekly.value;
        }
        recurrenceType.value = recurrenceType.value.capitalize!;
      }
      if (invoiceModel.recurringInvoiceStartDateTimestamp > 0) {
        recurrenceStartDate.value = DateFormat("MM/dd/yyyy").format(
            DateTime.fromMillisecondsSinceEpoch(
                invoiceModel.recurringInvoiceStartDateTimestamp * 1000));
        int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (nowTimestamp > invoiceModel.recurringInvoiceStartDateTimestamp) {
          isRecurrenceStarted = true;
        }
      }
      if (invoiceModel.recurringInvoiceEndDateTimestamp > 0) {
        recurrenceEndDate.value = DateFormat("MM/dd/yyyy").format(
            DateTime.fromMillisecondsSinceEpoch(
                invoiceModel.recurringInvoiceEndDateTimestamp * 1000));
      }
    }
    if (companyProfileController.selectedMeasurementSystem.value ==
        AppConstant.usImperial) {
      serviceTypes = invoiceController.priceController.serviceTypeImperial;
    } else {
      serviceTypes = invoiceController.priceController.serviceTypeMetric;
    }
    invoiceController.priceController.defaultServiceType.value =
        serviceTypes[0];
    isPackageEstimate =
        invoiceModel.estimateType == AppConstant.packageEstimate;
    hasEditPermission = invoicePermissions.contains(AppConstant.editInvoices);
    showPrices = invoicePermissions.contains(AppConstant.viewPrices);
    if (invoiceModel.taxRatePer == 0 && companyTax > 0) {
      taxEnabled = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (invoiceController.priceController.existServiceList.isEmpty) {
        await invoiceController.priceController.getServices();
      }
      loading.value = false;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).requestFocus(FocusNode());
      },
      child: SingleChildScrollView(
        child: Obx(() {
          var invoiceModel = invoiceController.currentInvoiceModel.value;
          var customerModel = invoiceController.currentCustomerModel.value;
          if ((!loading.value)) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                children: [
                  SizedBox(height: 15.h),
                  _buildSectionWidget(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Customer Details",
                          style: TextStyle(
                            color: CustomColor.buttonColor.value,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 5.h),
                            if (!widget.isEstimate && !widget.isEdit)
                              Column(
                                children: [
                                  DropDownSearchWidget(
                                    enabled: isEditEnabled,
                                    hintText: "Customer Name",
                                    items: invoiceController
                                        .addCustomerController.customersNameList
                                        .map((val) {
                                      return val;
                                    }).toList(),
                                    onItemChanged: (val) async {
                                      invoiceController.setCustomerData(val);
                                    },
                                    selectedItem: invoiceModel.customerName.obs,
                                  ),
                                  if (isEditEnabled &&
                                      hasAddCustomerPermission())
                                    GestureDetector(
                                      onTap: () {
                                        Get.to(() => const AddCustomerScreen(
                                              isEdit: false,
                                              isBack: true,
                                              isInvoice: true,
                                              isEstimate: false,
                                              isInspection: false,
                                            ));
                                      },
                                      child: Align(
                                        alignment: Alignment.topRight,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                            right: 10,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.add,
                                                color:
                                                    CustomColor.iconColor.value,
                                                size: 15,
                                              ),
                                              Text(
                                                "Create New Customer",
                                                style: pBold12.copyWith(
                                                  color: (themeController
                                                          .isDarkMode.value)
                                                      ? CustomColor
                                                          .bgColor.value
                                                      : CustomColor
                                                          .lightYellow.value,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  SizedBox(height: 5.h),
                                ],
                              ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              child: Column(
                                children: [
                                  customerDetail(
                                    key: "Name",
                                    val: invoiceModel.customerName,
                                  ),
                                  customerDetail(
                                    key: "Address",
                                    val: invoiceModel.address,
                                  ),
                                  (customerModel.customerAddressesList.length <=
                                              1 ||
                                          widget.isEdit)
                                      ? Container()
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 10.0),
                                          child: Align(
                                            alignment: Alignment.topRight,
                                            child: InkWell(
                                              onTap: () {
                                                showModalBottomSheet(
                                                  shape:
                                                      const RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.only(
                                                      topLeft:
                                                          Radius.circular(25),
                                                      topRight:
                                                          Radius.circular(25),
                                                    ),
                                                  ),
                                                  constraints: BoxConstraints(
                                                    maxWidth: ResponsiveBuilder
                                                            .isMobile(context)
                                                        ? Get.width
                                                        : 1000,
                                                  ),
                                                  isScrollControlled: true,
                                                  context: context,
                                                  backgroundColor:
                                                      CustomColor.transparent,
                                                  builder: (context) =>
                                                      ChooseCustomerAddress(
                                                    addressesList: customerModel
                                                        .customerAddressesList,
                                                    onAddressSelected: (index) {
                                                      setCustomerAddress(index);
                                                    },
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                "view ${customerModel.customerAddressesList.length - 1} more",
                                                style: pBold12.copyWith(
                                                  fontSize: 16,
                                                  color: CustomColor
                                                      .buttonColor.value,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                  customerDetail(
                                    key: "Email",
                                    val: invoiceModel.email,
                                  ),
                                  customerDetail(
                                    key: "Mobile",
                                    val: invoiceModel.customerPhone,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                          ],
                        )
                      ],
                    ),
                  ),
                  SizedBox(height: 15.h),
                  _buildSectionWidget(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Invoice Details",
                              style: TextStyle(
                                color: CustomColor.buttonColor.value,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  "Invoice No",
                                  style: TextStyle(
                                    color: CustomColor.buttonColor.value,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Container(
                                  height: 30.h,
                                  width: 75.w,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: CustomColor.buttonColor.value,
                                      ),
                                    ),
                                  ),
                                  child: TextField(
                                    enabled: isEditEnabled,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                    ),
                                    controller: invoiceNoController,
                                    style: pRegular10.copyWith(
                                      color: CustomColor.bgColor.value,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                        SizedBox(height: 12.h),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 5.h),
                                    child: Text(
                                      "Issued Date",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: CustomColor.bgColor.value,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  InkWell(
                                    onTap: () async {
                                      if (isEditEnabled) {
                                        var date = await CustomDateTimeSelector
                                            .selectDate(
                                          context: context,
                                        );
                                        setInvoiceDate(date);
                                      }
                                    },
                                    child: Container(
                                      height: 45,
                                      decoration: BoxDecoration(
                                        color:
                                            (themeController.isDarkMode.value)
                                                ? CustomColor.text.value
                                                : CustomColor.white,
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                          color: CustomColor.lightGray.value,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(children: [
                                          Icon(
                                            AssetsUtility.calendar,
                                            color: CustomColor.bgColor.value,
                                          ),
                                          SizedBox(width: 5.w),
                                          Text(
                                            invoiceModel.invoiceDate,
                                            style: TextStyle(
                                              color: CustomColor.bgColor.value,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 5.h),
                                    child: Text(
                                      "Payment Term",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: CustomColor.bgColor.value,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  CustomDropDownFormField(
                                    isDisable: !isEditEnabled,
                                    color: (themeController.isDarkMode.value)
                                        ? CustomColor.text.value
                                        : CustomColor.white,
                                    height: 45,
                                    fontSize: 16,
                                    isHint: false,
                                    list: invoiceController.paymentTermList,
                                    hintText: "Due Upon Receipt",
                                    name: invoiceModel.paymentTerm.obs,
                                    showValue: true,
                                    onChange: (value) {
                                      setInvoicePaymentTerm(value);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 15.h),
                  _buildSectionWidget(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isEditEnabled && !isPackageEstimate)
                          const AddInvoiceServiceButton(),
                        SizedBox(height: 10.h),
                        Container(
                          height: 40.h,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: CustomColor.lightGray.value,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10.w),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 8,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      "Service Name",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: CustomColor.buttonColor.value,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    "($currencySymbol) Amount",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: CustomColor.buttonColor.value,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        !isPackageEstimate
                            ? ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: invoiceModel.serviceList.length,
                                shrinkWrap: true,
                                itemBuilder: (context, index) {
                                  return InvoiceServiceItemWidget(
                                    invoiceModel: invoiceModel,
                                    invoiceController: invoiceController,
                                    index: index,
                                    showPrices: showPrices,
                                    isEditEnabled: isEditEnabled,
                                    currencySymbol: currencySymbol,
                                  );
                                },
                              )
                            : ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: invoiceModel.packagesList.length,
                                shrinkWrap: true,
                                itemBuilder: (context, index) {
                                  var packageModel =
                                      invoiceModel.packagesList[index];
                                  return _buildPackageItemWidget(packageModel);
                                },
                              ),
                        if (isEditEnabled && !isPackageEstimate)
                          AddInvoiceCustomServiceWidget(
                            callback: () {
                              var lastService = invoiceController
                                  .priceController.existServiceList.last;
                              var service = InvoiceService(
                                serviceId: lastService.docId,
                                lengthOfService: lastService.lengthOfService,
                                onlineSelfSchedule:
                                    lastService.onlineSelfSchedule,
                                total: lastService.sqFtPrice.toStringAsFixed(2),
                                serviceImageUrl: lastService.image,
                                serviceDescription:
                                    lastService.serviceDescription,
                                serviceName: lastService.serviceName,
                                customServiceImageUrl: "",
                              );
                              invoiceController
                                  .currentInvoiceModel.value.serviceList
                                  .add(service);
                              invoiceController.updateInvoiceTotals();
                            },
                            serviceTypes: serviceTypes,
                            invoiceController: invoiceController,
                            myPriceController:
                                invoiceController.priceController,
                            themeController: themeController,
                          ),
                        SizedBox(height: 20.h),
                        Text(
                          "Billing Information",
                          style: TextStyle(
                            color: CustomColor.buttonColor.value,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5.w),
                          child: Column(
                            children: [
                              _buildTotalsSection(),
                              SizedBox(height: 8.h),
                              if (isEditEnabled)
                                Container(
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (themeController.isDarkMode.value)
                                        ? CustomColor.text.value
                                        : CustomColor.themeColor.value,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Add Taxes",
                                        style: pBold12.copyWith(
                                            fontSize: 16,
                                            color: CustomColor.bgColor.value),
                                      ),
                                      CupertinoSwitch(
                                        value: taxEnabled,
                                        onChanged: (v) {
                                          setState(() {
                                            taxEnabled = !taxEnabled;
                                          });
                                          setInvoiceTax();
                                        },
                                        activeColor:
                                            CustomColor.lightYellow.value,
                                      ),
                                    ],
                                  ),
                                ),
                              SizedBox(height: 8.h),
                              Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 10),
                                    child: Text(
                                      "Payment Status",
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: CustomColor.textFieldText.value,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    flex: 3,
                                    child: SizedBox(
                                      height: 40,
                                      child: CustomDropDownFormField(
                                        list:
                                            invoiceController.paymentStatusList,
                                        hintText: AppConstant.pending,
                                        name: invoiceModel.paymentStatus.obs,
                                        onChange: (value) {
                                          setInvoiceStatus(value);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(start: 0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        if (isEditEnabled) {
                                          setState(() {
                                            invoiceModel.isRecurring =
                                                !invoiceModel.isRecurring;
                                          });
                                        }
                                      },
                                      child: Row(
                                        children: [
                                          Icon(
                                            (invoiceModel.isRecurring)
                                                ? Icons.check_box_rounded
                                                : Icons
                                                    .check_box_outline_blank_rounded,
                                            color:
                                                CustomColor.lightYellow.value,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            "Recurring Invoice",
                                            style: pBold16.copyWith(
                                              fontSize: 12,
                                              color: CustomColor
                                                  .textFieldText.value,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        if (isEditEnabled) {
                                          setState(() {
                                            invoiceModel.isRecurring =
                                                !invoiceModel.isRecurring;
                                          });
                                        }
                                      },
                                      child: Row(
                                        children: [
                                          Icon(
                                            (!invoiceModel.isRecurring)
                                                ? Icons.check_box_rounded
                                                : Icons
                                                    .check_box_outline_blank_rounded,
                                            color:
                                                CustomColor.lightYellow.value,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            "One-Time Invoice",
                                            style: pBold16.copyWith(
                                              fontSize: 12,
                                              color: CustomColor
                                                  .textFieldText.value,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (invoiceModel.isRecurring)
                                Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: CustomDropDownFormField(
                                    isDisable: !isEditEnabled,
                                    validator: (value) =>
                                        Validators.validateRequired(
                                      value,
                                      "Recurrence type",
                                    ),
                                    showValue: recurrenceType.value.isNotEmpty,
                                    hintText: "Recurrence type",
                                    list: RecurrenceType.values
                                        .map((e) => e
                                            .toString()
                                            .split(".")
                                            .last
                                            .capitalize!)
                                        .toList(),
                                    name: recurrenceType,
                                  ),
                                ),
                              if (recurrenceType.value.isNotEmpty &&
                                  invoiceModel.isRecurring)
                                Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (!isRecurrenceStarted)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Start Date",
                                              style: pBold16.copyWith(
                                                  fontSize: 14,
                                                  color: CustomColor
                                                      .darkBlue.value),
                                            ),
                                            SizedBox(height: 5.h),
                                            InkWell(
                                              onTap: () async {
                                                if (isEditEnabled) {
                                                  DateTime formattedStartDate =
                                                      DateTime.now();
                                                  String date =
                                                      await CustomDateTimeSelector
                                                          .selectDate(
                                                    context: context,
                                                    dateSelect: "",
                                                    passFirstDate:
                                                        formattedStartDate,
                                                    initialDate:
                                                        formattedStartDate,
                                                  );
                                                  recurrenceStartDate.value =
                                                      date;
                                                  recurrenceStartDate.refresh();
                                                  recurrenceEndDate.value = "";
                                                  debugPrint("date::$date");
                                                }
                                              },
                                              child: Container(
                                                height: 45.h,
                                                width: Get.width * 0.35,
                                                decoration: BoxDecoration(
                                                  color: CustomColor.white,
                                                  borderRadius:
                                                      BorderRadius.circular(25),
                                                  border: Border.all(
                                                    color: CustomColor
                                                        .lightGray.value,
                                                  ),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8.0),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        AssetsUtility.calendar,
                                                        color: CustomColor
                                                            .darkBlue.value,
                                                        // height: 17.h,
                                                        // width: 17.w,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          recurrenceStartDate
                                                              .value,
                                                          style:
                                                              pBold16.copyWith(
                                                            color: CustomColor
                                                                .darkBlue.value,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "End Date",
                                            style: pBold16.copyWith(
                                              fontSize: 14,
                                              color: CustomColor.darkBlue.value,
                                            ),
                                          ),
                                          SizedBox(
                                            height: 5.h,
                                          ),
                                          InkWell(
                                            onTap: () async {
                                              if (isEditEnabled) {
                                                var dateFormat =
                                                    DateFormat('MM/dd/yyyy');
                                                DateTime formattedStartDate =
                                                    DateTime.now().add(
                                                        const Duration(
                                                            days: 2));
                                                if (!isRecurrenceStarted) {
                                                  if (recurrenceStartDate
                                                      .value.isNotEmpty) {
                                                    formattedStartDate = dateFormat
                                                        .parse(
                                                            recurrenceStartDate
                                                                .value)
                                                        .add(const Duration(
                                                            days: 2));
                                                  }
                                                } else {
                                                  formattedStartDate =
                                                      DateTime.now().add(
                                                          const Duration(
                                                              days: 1));
                                                }
                                                String date =
                                                    await CustomDateTimeSelector
                                                        .selectDate(
                                                  context: context,
                                                  dateSelect: "",
                                                  passFirstDate:
                                                      formattedStartDate,
                                                  initialDate:
                                                      formattedStartDate,
                                                );
                                                recurrenceEndDate.value = date;
                                                recurrenceEndDate.refresh();
                                                debugPrint("date::$date");
                                              }
                                            },
                                            child: Container(
                                              height: 45.h,
                                              width: Get.width * 0.35,
                                              decoration: BoxDecoration(
                                                color: CustomColor.white,
                                                borderRadius:
                                                    BorderRadius.circular(25),
                                                border: Border.all(
                                                    color: CustomColor
                                                        .lightGray.value),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      AssetsUtility.calendar,
                                                      color: CustomColor
                                                          .darkBlue.value,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Expanded(
                                                      child: Text(
                                                        recurrenceEndDate.value,
                                                        style: pBold16.copyWith(
                                                          color: CustomColor
                                                              .darkBlue.value,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              if (checkShowCancelRecurringOption())
                                Column(
                                  children: [
                                    SizedBox(height: 20.h),
                                    CustomButton(
                                      text: "Cancel Recurrence",
                                      function: () async {
                                        if (isEditEnabled) {
                                          setState(() {
                                            invoiceModel.isRecurring =
                                                !invoiceModel.isRecurring;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 25.h),
                  if (companyProfileController.stripeMerchantId.isEmpty &&
                      invoiceModel.isRecurring)
                    const CompleteBankInfoWidget(),
                  Container(
                    width: Get.width,
                    decoration: BoxDecoration(
                      color: (themeController.isDarkMode.value)
                          ? CustomColor.text.value
                          : CustomColor.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [containerLowShadow()],
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 5.h,
                          ),
                          Text(
                            "Client Message",
                            style: TextStyle(
                                color: CustomColor.buttonColor.value,
                                fontSize: 20,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(
                            height: 10.h,
                          ),
                          CustomTextField(
                            readOnly: !isEditEnabled,
                            radius: 15,
                            color: (themeController.isDarkMode.value)
                                ? CustomColor.text.value
                                : CustomColor.white,
                            borderColor: CustomColor.bgColor.value,
                            maxLines: 5,
                            controller: clientMessageController,
                            textColor: CustomColor.black.value,
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                          ),
                          SizedBox(
                            height: 5.h,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  if (isEditEnabled)
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () {
                          showModalBottomSheet(
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(25),
                                topRight: Radius.circular(25),
                              ),
                            ),
                            constraints: BoxConstraints(
                              maxWidth: ResponsiveBuilder.isMobile(context)
                                  ? Get.width
                                  : 1000,
                            ),
                            backgroundColor: CustomColor.transparent,
                            context: context,
                            builder: (BuildContext context) {
                              return PickImageSheet(
                                onCamera: () {
                                  invoiceController.getInvoiceAttachment(
                                    imageSource: ImageSource.camera,
                                  );
                                },
                                onGallery: () {
                                  invoiceController.getInvoiceAttachment(
                                    imageSource: ImageSource.gallery,
                                  );
                                },
                              );
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (themeController.isDarkMode.value)
                                ? CustomColor.text.value
                                : CustomColor.themeColor.value,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Attach Photos",
                            style: pBold12.copyWith(
                              fontSize: 16,
                              color: CustomColor.bgColor.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(height: 10.h),
                  if (invoiceModel.documents.isNotEmpty)
                    AttachmentsGalleryWidget(
                      attachmentsList: invoiceModel.documents.obs,
                      onRemove: invoiceController.deleteInvoiceAttachment,
                    ),
                  if (invoiceModel.documents.isNotEmpty) SizedBox(height: 10.h),
                  InvoicePaymentMethodsDialog(
                    acceptedMethods: invoiceModel.invoiceAcceptedPaymentMethods,
                    readOnly: !isEditEnabled,
                  ),
                  SizedBox(height: 10.h),
                  InvoicePaymentTermsDialog(
                    paymentTerms: invoiceModel.invoicePaymentTerms,
                    readOnly: !isEditEnabled,
                  ),
                  SizedBox(height: 30.h),
                  hasEditPermission && invoiceModel.paidAt == 0
                      ? CustomButton(
                          text: "Save & Continue",
                          function: () async {
                            await saveInvoice();
                            if (!Get.isSnackbarOpen) {
                              widget.onSave();
                            }
                          },
                        )
                      : CustomButton(
                          text: "Send Email",
                          function: () async {
                            InvoiceModel invoiceModel =
                                invoiceController.currentInvoiceModel.value;
                            if (invoiceModel.email.isNotEmpty) {
                              EmailTemplateController emailTemplateController =
                                  Get.put(EmailTemplateController());
                              Loader.showLoader();
                              await emailTemplateController
                                  .getInvoiceEmailTemplate();
                              Loader.hideLoader();
                              String customerId = invoiceModel.customerId;
                              String customerFirstName = "",
                                  customerLastName = "";
                              int customerIndex = invoiceController
                                  .addCustomerController.customersData
                                  .indexWhere(
                                      (element) => element.docId == customerId);
                              if (customerIndex != -1) {
                                customerFirstName = invoiceController
                                    .addCustomerController
                                    .customersData[customerIndex]
                                    .firstName;
                                customerLastName = invoiceController
                                    .addCustomerController
                                    .customersData[customerIndex]
                                    .lastName;
                              }
                              final companyName = companyProfileController
                                  .companyInfo.value.companyName;

                              String imgLink = companyProfileController
                                  .companyInfo.value.image;
                              String companyAddress = companyProfileController
                                  .companyInfo.value.address;
                              String companyPhone = companyProfileController
                                  .companyInfo.value.phoneNumber;
                              String template = emailTemplateController
                                  .invoiceEmailBodyController.value.text;
                              String buttonLink =
                                  AppConstant.invoicesPublicLinkPrefix +
                                      invoiceModel.docId;
                              String invoiceTotal =
                                  "$currencySymbol${(!invoiceModel.isDepositPaid) ? invoiceModel.total : (invoiceModel.total - invoiceModel.depositAmount).toStringAsFixed(2)}";
                              Get.to(() => SendEmailScreen(
                                    customerEmail: invoiceModel.email,
                                    customerFirstName: customerFirstName,
                                    customerLastName: customerLastName,
                                    customerName: invoiceModel.customerName,
                                    customerPhone: invoiceModel.customerPhone,
                                    customerAddress: invoiceModel.address,
                                    emailSubject: emailTemplateController
                                        .invoiceEmailSubjectController
                                        .value
                                        .text,
                                    emailBodyTemplate: template,
                                    companyName: companyName,
                                    companyAddress: companyAddress,
                                    companyPhone: companyPhone,
                                    companyImageLink: imgLink,
                                    actionButtonLink: buttonLink,
                                    header:
                                        "INVOICE ${invoiceModel.invoiceNumber}",
                                    total: invoiceTotal,
                                    serviceNamesList:
                                        invoiceModel.serviceList.isNotEmpty
                                            ? invoiceModel.serviceList
                                                .map((e) => e.serviceName)
                                                .toList()
                                            : invoiceModel.packagesList
                                                .map((e) => e.packageName)
                                                .toList(),
                                  ));
                            } else {
                              ShowSnackBar.error("Invalid customer email");
                            }
                          },
                        ),
                  SizedBox(height: 30.h),
                ],
              ),
            );
          } else {
            return SizedBox(
              height: Get.height,
              child: Center(
                child: CircularProgressIndicator(
                  color: CustomColor.black.value,
                ),
              ),
            );
          }
        }),
      ),
    );
  }

  Widget _buildSectionWidget({required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      width: Get.width,
      decoration: BoxDecoration(
        color: (themeController.isDarkMode.value)
            ? CustomColor.text.value
            : CustomColor.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [containerLowShadow()],
      ),
      child: child,
    );
  }

  Widget _buildPackageItemWidget(InvoicePackageModel packageModel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packageModel.packageName,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: CustomColor.bgColor.value,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                if (packageModel.packageDescription.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 15),
                    child: Text(
                      packageModel.packageDescription,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: CustomColor.bgColor.value,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              showPrices
                  ? currencySymbol +
                      packageModel.packageTotal.toStringAsFixed(2)
                  : "",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CustomColor.bgColor.value,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection() {
    var invoiceModel = invoiceController.currentInvoiceModel.value;
    return TotalsSectionWidget(
      isEditEnabled: isEditEnabled,
      subTotalValue: invoiceModel.subTotal,
      discountAmount: invoiceModel.discountAmount,
      discountPercentage: invoiceModel.discountPer,
      taxAmount: invoiceModel.taxAmount,
      taxPercentage: invoiceModel.taxRatePer,
      convenienceFeePercentage: invoiceModel.convenienceFeePercentage,
      convenienceFeeAmount: invoiceModel.convenienceFeeAmount,
      totalValue: invoiceModel.total,
      depositValue: invoiceModel.depositPercentageEnabled
          ? invoiceModel.depositPercentage
          : invoiceModel.depositAmount,
      discountPercentageEnabled: invoiceModel.discountPercentageEnabled,
      onDiscountValueChanged: (value) {
        if (invoiceModel.discountPercentageEnabled) {
          invoiceModel.discountPer = value.toPrecision(2);
        } else {
          invoiceModel.discountAmount = value.toPrecision(2);
        }
        invoiceController.updateInvoiceTotals();
      },
      onTaxValueChanged: (value) {
        invoiceModel.taxRatePer = value.toPrecision(2);
        invoiceController.updateInvoiceTotals();
      },
      onConvenienceFeeValueChanged: (value) {
        invoiceModel.convenienceFeePercentage = value;
        invoiceController.updateInvoiceTotals();
      },
      onDepositValueChanged: (value) {
        if (invoiceModel.depositPercentageEnabled) {
          invoiceModel.depositPercentage = value;
        } else {
          invoiceModel.depositAmount = value;
        }
        invoiceController.updateInvoiceTotals();
      },
      onDiscountPercentageEnabledChanged: (value) {
        invoiceModel.discountPercentageEnabled = value;
        invoiceController.currentInvoiceModel.refresh();
        // invoiceController.updateDiscountPercentageEnabled(value);
      },
      currencySymbol: currencySymbol,
      isDepositPaid: invoiceModel.isDepositPaid,
    );
  }

  Widget billingInformationWidget(
      {required String title, required Widget secondWidget}) {
    return Container(
      height: 45.h,
      decoration: BoxDecoration(
        color: (themeController.isDarkMode.value)
            ? CustomColor.text.value
            : CustomColor.lightGray.value,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Text(
                title,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: CustomColor.bgColor.value,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // const Expanded(flex: 4, child: SizedBox()),
          SizedBox(width: 10.w),
          Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: secondWidget,
              )),
        ],
      ),
    );
  }

  Widget billingRateInformationWidget({
    required String title,
    required Widget secondWidget,
    required Widget amount,
    bool expandSecondWidget = false,
  }) {
    return Container(
      height: 30.h,
      decoration: BoxDecoration(
        color: (themeController.isDarkMode.value)
            ? CustomColor.text.value
            : CustomColor.lightGray.value,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Text(
                title,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: CustomColor.bgColor.value,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(flex: expandSecondWidget ? 4 : 2, child: secondWidget),
          SizedBox(width: 10.w),
          Expanded(
            flex: 2,
            child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: amount,
                )),
          ),
        ],
      ),
    );
  }

  Widget customerDetail({required String key, required String val}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Text(
              "$key:  ",
              style: pSemiBold20.copyWith(
                  color: CustomColor.bgColor.value, fontSize: 14),
            ),
          ),
          const SizedBox(
            width: 10, //ResponsiveBuilder.isMobile(context) ? 4.w : 1.w,
          ),
          Expanded(
            flex: 4,
            child: Text(
              val,
              style: pSemiBold20.copyWith(
                  color: CustomColor.bgColor.value, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

String formatReccurenceTypeToIntervalName(String type) {
  if (type == RecurrenceType.daily.value) {
    return "day";
  } else if (type == RecurrenceType.weekly.value) {
    return "week";
  } else if (type == RecurrenceType.biweekly.value) {
    return "biweek";
  } else if (type == RecurrenceType.monthly.value) {
    return "month";
  } else if (type == RecurrenceType.yearly.value) {
    return "year";
  } else {
    return "day";
  }
}

String formatIntervalNameToRecurrenceTypeValue(String type) {
  switch (type) {
    case "day":
      return RecurrenceType.daily.value;
    case "week":
      return RecurrenceType.weekly.value;
    case "month":
      return RecurrenceType.monthly.value;
    case "year":
      return RecurrenceType.yearly.value;
    default:
      return RecurrenceType.daily.value;
  }
}
