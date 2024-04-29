import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ribbon_widget/ribbon_widget.dart';

import '../../common/assets_utility.dart';
import '../../common/constant.dart';
import '../../common/custom_appbar.dart';
import '../../common/custom_button.dart';
import '../../common/custom_color.dart';
import '../../common/loader.dart';
import '../../common/responsive_builder.dart';
import '../../common/snackbar.dart';
import '../../common/text_style.dart';
import '../../controllers/company_profile_controller.dart';
import '../../controllers/invoice_controller.dart';
import '../../controllers/email_templates_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../model/invoice_model.dart';
import '../estimates/image_network_screen.dart';
import '../estimates/pdf_viewer.dart';
import '../send_email/send_email_screen.dart';
import '../send_text/send_text_screen.dart';

class PreviewInvoiceScreen extends StatefulWidget {
  final VoidCallback onBack;
  final bool hasAppBar;
  const PreviewInvoiceScreen({
    super.key,
    required this.onBack,
    this.hasAppBar = false,
  });

  @override
  State<PreviewInvoiceScreen> createState() => _PreviewInvoiceScreenState();
}

class _PreviewInvoiceScreenState extends State<PreviewInvoiceScreen> {
  ThemeController themeController = Get.find();
  CompanyProfileController companyProfileController = Get.find();
  InvoiceController invoiceController = Get.find();
  InvoiceModel invoiceModel = InvoiceModel.empty();
  bool showPrices = false;
  bool hasSharePermission = false;
  @override
  void initState() {
    invoiceModel = InvoiceModel.fromMap(
      data: invoiceController.currentInvoiceModel.value.toMap(),
      includePrices: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() {
        showPrices = invoiceController.checkInvoiceUserPermissions(
                permission: AppConstant.viewPrices) ||
            invoiceController.checkInvoiceUserPermissions(
                permission: AppConstant.editInvoices) ||
            invoiceController.checkInvoiceUserPermissions(
                permission: AppConstant.markInvoicesAsPaid);
        hasSharePermission = invoiceController.checkInvoiceUserPermissions(
            permission: AppConstant.share);
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    String currencySymbol = invoiceController
        .estimatesController.companyFormController.currencySymbol.value;

    return Scaffold(
      appBar: widget.hasAppBar
          ? customAppBar(
              title: "Preview Invoice",
              context: context,
              isBack: true,
            )
          : null,
      backgroundColor: (themeController.isDarkMode.value)
          ? CustomColor.themeColor.value
          : CustomColor.white,
      extendBody: true,
      bottomNavigationBar: Container(
        color: Colors.transparent,
        height: 130.h,
        margin: EdgeInsets.only(bottom: 20.h),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.transparent,
                padding: const EdgeInsets.only(
                  right: 10,
                  bottom: 20,
                ),
                alignment: Alignment.bottomRight,
                child: hasSharePermission
                    ? SpeedDial(
                        backgroundColor: CustomColor.buttonColor.value,
                        icon: Icons.send,
                        iconTheme: const IconThemeData(color: Colors.white),
                        overlayColor: Colors.black,
                        overlayOpacity: 0.4,
                        spacing: 10,
                        spaceBetweenChildren: 10,
                        children: [
                          SpeedDialChild(
                            child: const Icon(
                              Icons.mail_outline,
                            ),
                            label: "Email",
                            onTap: () async {
                              if (invoiceModel.email.isNotEmpty) {
                                EmailTemplateController
                                    emailTemplateController =
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
                                    .indexWhere((element) =>
                                        element.docId == customerId);
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
                          SpeedDialChild(
                              child: const Icon(
                                Icons.message_outlined,
                              ),
                              label: "Text Through App",
                              onTap: () async {
                                if (true) {
                                  EmailTemplateController
                                      emailTemplateController =
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
                                      .indexWhere((element) =>
                                          element.docId == customerId);
                                  String customerPhone = "";
                                  if (customerIndex != -1) {
                                    customerFirstName = invoiceController
                                        .addCustomerController
                                        .customersData[customerIndex]
                                        .firstName;
                                    customerLastName = invoiceController
                                        .addCustomerController
                                        .customersData[customerIndex]
                                        .lastName;
                                    customerPhone = invoiceController
                                        .addCustomerController
                                        .customersData[customerIndex]
                                        .phoneNumber;
                                  }

                                  final companyName = companyProfileController
                                      .companyInfo.value.companyName;

                                  String imgLink = companyProfileController
                                      .companyInfo.value.image;
                                  String companyAddress =
                                      companyProfileController
                                          .companyInfo.value.address;
                                  String companyPhone = companyProfileController
                                      .companyInfo.value.phoneNumber;
                                  String template = emailTemplateController
                                      .invoiceSmsBodyController.value.text;
                                  String buttonLink =
                                      AppConstant.invoicesPublicLinkPrefix +
                                          invoiceModel.docId;
                                  String invoiceTotal =
                                      "$currencySymbol${(!invoiceModel.isDepositPaid) ? invoiceModel.total : (invoiceModel.total - invoiceModel.depositAmount).toStringAsFixed(2)}";
                                  Get.to(() => SendTextScreen(
                                        customerEmail: invoiceModel.email,
                                        customerFirstName: customerFirstName,
                                        customerLastName: customerLastName,
                                        customerName: invoiceModel.customerName,
                                        customerPhone: customerPhone,
                                        customerAddress: invoiceModel.address,
                                        smsBodyTemplate: template,
                                        companyName: companyName,
                                        companyAddress: companyAddress,
                                        companyPhone: companyPhone,
                                        companyImageLink: imgLink,
                                        actionButtonLink: buttonLink,
                                        header:
                                            "INVOICE ${invoiceModel.invoiceNumber}",
                                        total: invoiceTotal,
                                        isEstimate: false,
                                        serviceNamesList:
                                            invoiceModel.serviceList.isNotEmpty
                                                ? invoiceModel.serviceList
                                                    .map((e) => e.serviceName)
                                                    .toList()
                                                : invoiceModel.packagesList
                                                    .map((e) => e.packageName)
                                                    .toList(),
                                      ));
                                }
                              }),
                          if (!kIsWeb)
                            SpeedDialChild(
                              child: const Icon(Icons.message_outlined),
                              label: "Text Through Phone",
                              // companyProfileController.companyNameController.text
                              onTap: () async {
                                String customerPhone =
                                    invoiceModel.customerPhone;
                                if (customerPhone.isEmpty) {
                                  for (var customer in invoiceController
                                      .estimatesController
                                      .customerController
                                      .customersData) {
                                    if (customer.docId ==
                                        invoiceModel.customerId) {
                                      customerPhone =
                                          "+${customer.countryCode}${customer.phoneNumber}";
                                    }
                                  }
                                }
                                if (customerPhone.isNotEmpty) {
                                  var status = await Permission.sms.status;
                                  if (!status.isGranted) {
                                    await Permission.sms.request();
                                  }
                                  EmailTemplateController
                                      emailTemplateController =
                                      Get.put(EmailTemplateController());

                                  Loader.showLoader();
                                  await emailTemplateController
                                      .getInvoiceEmailTemplate();
                                  Loader.hideLoader();
                                  List<String> serviceNamesList =
                                      invoiceModel.serviceList.isNotEmpty
                                          ? invoiceModel.serviceList
                                              .map((e) => e.serviceName)
                                              .toList()
                                          : invoiceModel.packagesList
                                              .map((e) => e.packageName)
                                              .toList();
                                  String companyName = companyProfileController
                                      .companyInfo.value.companyName;
                                  String customerName =
                                      invoiceModel.customerName;
                                  String invoiceTotal =
                                      "${invoiceController.estimatesController.companyFormController.currencySymbol.value}${(!invoiceModel.isDepositPaid) ? invoiceModel.total : (invoiceModel.total - invoiceModel.depositAmount).toStringAsFixed(2)}";
                                  String invoiceLink =
                                      AppConstant.invoicesPublicLinkPrefix +
                                          invoiceModel.docId;
                                  Map<String, dynamic> variablesMap = {
                                    "@${AppConstant.companyName}": companyName,
                                    "@${AppConstant.customerName}":
                                        customerName,
                                    "@${AppConstant.invoiceTotal}":
                                        invoiceTotal,
                                    "@${AppConstant.serviceList}":
                                        serviceNamesList.join(", "),
                                    "@${AppConstant.invoiceLink}": invoiceLink,
                                  };
                                  String smsBody =
                                      emailTemplateController.replaceVariables(
                                    text: emailTemplateController
                                        .invoiceSmsBodyController.value.text,
                                    variablesMap: variablesMap,
                                  );
                                  String message = "$smsBody\n\n$invoiceLink";
                                  List<String> recipents = [customerPhone];
                                  String result = await sendSMS(
                                    message: message,
                                    recipients: recipents,
                                    sendDirect: false,
                                  ).catchError((onError) {
                                    debugPrint(onError.toString());
                                    return onError;
                                  });
                                  debugPrint(result);
                                } else {
                                  ShowSnackBar.error(
                                      "Invalid customer phone number");
                                }
                              },
                            ),
                          if (true)
                            SpeedDialChild(
                              child: const Icon(Icons.link),
                              label: "Copy Link",
                              onTap: () async {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: AppConstant.invoicesPublicLinkPrefix +
                                        invoiceModel.docId,
                                  ),
                                ).then((value) => {
                                      ShowSnackBar.success(
                                          "Link Copied to Clipboard")
                                    });
                              },
                            )
                        ],
                      )
                    : null,
              ),
              Container(
                height: 40,
                color: Colors.transparent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    CustomButton(
                      width: 90.w,
                      height: 40.h,
                      text: "Back",
                      function: () async {
                        widget.onBack();
                      },
                    ),
                    /* if (!kIsWeb)
                      button(
                        iconData: Icons.ios_share,
                        function: () async {
                          final Size size = MediaQuery.of(context).size;
                          const String mimeType = 'application/pdf';
                          Share.shareXFiles(
                            [
                              XFile.fromData(
                                invoiceController.invoiceGeneratedPdf,
                                mimeType: mimeType,
                              )
                            ],
                            text: 'Invoice',
                            sharePositionOrigin: Rect.fromLTWH(
                                0, 0, size.width, size.height / 2),
                          );
                        },
                      ), */
                    CustomButton(
                      width: 90.w,
                      height: 40.h,
                      text: "Exit & Close",
                      function: () async {
                        Get.back();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Ribbon(
          farLength: 50,
          nearLength: 100,
          title: invoiceModel.paymentStatus == "Paid" ? "Paid" : "Pending",
          color: CustomColor.buttonColor.value,
          child: Container(
            decoration: BoxDecoration(
                color: (themeController.isDarkMode.value)
                    ? CustomColor.themeColor.value
                    : CustomColor.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: Offset(0, 0))
                ]),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 10.h,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(
                        companyProfileController.companyInfo.value.image,
                        height: ResponsiveBuilder.isMobile(context) ? 120 : 120,
                        width: ResponsiveBuilder.isMobile(context) ? 120 : 120,
                        fit: BoxFit.fill,
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Invoice",
                            style: pBold16.copyWith(
                                fontSize: 14, color: CustomColor.black.value),
                          ),
                          Text(
                            "# ${invoiceModel.invoiceNumber}",
                            style: pRegular14.copyWith(
                              fontSize: 12,
                              color: CustomColor.black.value,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "Date Issued: ",
                            style: pBold16.copyWith(
                                fontSize: 14, color: CustomColor.black.value),
                          ),
                          SizedBox(
                            width: 5.w,
                          ),
                          Text(
                            invoiceModel.invoiceDate,
                            style: pRegular14.copyWith(
                                fontSize: 12, color: CustomColor.black.value),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 5.h,
                      ),
                      Row(
                        children: [
                          Text(
                            "Payable To:   ",
                            style: pBold16.copyWith(
                                fontSize: 14, color: CustomColor.black.value),
                          ),
                          SizedBox(
                            width: 5.w,
                          ),
                          Expanded(
                            child: Text(
                              companyProfileController
                                  .companyInfo.value.companyName,
                              style: pRegular14.copyWith(
                                fontSize: 12,
                                color: CustomColor.black.value,
                                overflow: TextOverflow.fade,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 5.h,
                      ),
                      Row(
                        children: [
                          Text(
                            "Balance Due: ",
                            style: pBold16.copyWith(
                                fontSize: 14, color: CustomColor.black.value),
                          ),
                          SizedBox(
                            width: 5.w,
                          ),
                          Text(
                            !showPrices
                                ? ""
                                : (invoiceModel.isDepositPaid)
                                    ? (currencySymbol +
                                        (invoiceModel.total -
                                                invoiceModel.depositAmount)
                                            .toStringAsFixed(2))
                                    : (currencySymbol +
                                        invoiceModel.total.toStringAsFixed(2)),
                            style: pRegular14.copyWith(
                                fontSize: 12, color: CustomColor.black.value),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    "From:",
                    style: pBold16.copyWith(color: CustomColor.black.value),
                  ),
                  Text(
                    companyProfileController.companyNameController.value.text,
                    style: pBold16.copyWith(
                      fontSize: 14,
                      color: CustomColor.black.value,
                    ),
                  ),
                  Text(
                    companyProfileController.companyInfo.value.address,
                    style: pRegular14.copyWith(color: CustomColor.black.value),
                  ),
                  Text(
                    "Phone: ${companyProfileController.companyInfo.value.phoneNumber}",
                    style: pRegular14.copyWith(color: CustomColor.black.value),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    "To:",
                    style: pBold16.copyWith(color: CustomColor.black.value),
                  ),
                  Text(
                    invoiceModel.customerName,
                    style: pRegular14.copyWith(color: CustomColor.black.value),
                  ),
                  if (invoiceModel.address.isNotEmpty)
                    Text(
                      invoiceModel.address,
                      style:
                          pRegular14.copyWith(color: CustomColor.black.value),
                    ),
                  // if (invoiceModel!.email.isNotEmpty)
                  //   Text(
                  //     "Email: " + invoiceModel!.email,
                  //     style: pRegular14.copyWith(
                  //         color: CustomColor.black.value),
                  //   ),
                  if (invoiceModel.customerPhone.isNotEmpty)
                    Text(
                      "Phone: ${invoiceModel.customerPhone}",
                      style:
                          pRegular14.copyWith(color: CustomColor.black.value),
                    ),
                  SizedBox(
                    height: 10.h,
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.w),
                    height: 30.h,
                    color: CustomColor.lightGray.value,
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(
                          "DESCRIPTION",
                          style: pBold12.copyWith(
                              fontSize: 13, color: CustomColor.darkBlue.value),
                        )),
                        SizedBox(
                          width: 80.w,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "AMOUNT",
                              style: pBold12.copyWith(
                                  fontSize: 13,
                                  color: CustomColor.darkBlue.value),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                  invoiceModel.serviceList.isNotEmpty
                      ? ListView.builder(
                          padding: const EdgeInsets.all(0),
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: invoiceModel.serviceList.length,
                          itemBuilder: (context, index) {
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 5.w, vertical: 10.h),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            height: 5.h,
                                          ),
                                          Text(
                                            invoiceModel
                                                .serviceList[index].serviceName,
                                            style: pBold16.copyWith(
                                              fontSize: 13,
                                              color: CustomColor.black.value,
                                            ),
                                          ),
                                          (invoiceModel
                                                  .serviceList[index]
                                                  .serviceDescription
                                                  .isNotEmpty)
                                              ? Text(
                                                  invoiceModel
                                                      .serviceList[index]
                                                      .serviceDescription,
                                                  style: pRegular14.copyWith(
                                                      fontSize: 12,
                                                      color: CustomColor
                                                          .black.value))
                                              : const SizedBox.shrink(),
                                        ],
                                      )),
                                      Padding(
                                        padding: EdgeInsets.only(top: 5.h),
                                        child: SizedBox(
                                          width: 80.w,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                                showPrices
                                                    ? currencySymbol +
                                                        double.parse(invoiceModel
                                                                .serviceList[
                                                                    index]
                                                                .total)
                                                            .toStringAsFixed(2)
                                                    : "",
                                                style: pRegular14.copyWith(
                                                    fontSize: 13,
                                                    color: CustomColor
                                                        .black.value)),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5.h,
                                  ),
                                  DottedLine(
                                    direction: Axis.horizontal,
                                    lineLength: double.infinity,
                                    lineThickness: 1.0,
                                    dashLength: 1.0,
                                    dashColor:
                                        (themeController.isDarkMode.value)
                                            ? CustomColor.lightGray.value
                                            : CustomColor.darkGray.value,
                                    dashRadius: 50,
                                    dashGapLength: 2.0,
                                  )
                                ],
                              ),
                            );
                          })
                      : ListView.builder(
                          padding: const EdgeInsets.all(0),
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: invoiceModel.packagesList.length,
                          itemBuilder: (context, index) {
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 5.w, vertical: 10.h),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            height: 5.h,
                                          ),
                                          Text(
                                            invoiceModel.packagesList[index]
                                                .packageName,
                                            style: pBold16.copyWith(
                                              fontSize: 13,
                                              color: CustomColor.black.value,
                                            ),
                                          ),
                                          (invoiceModel
                                                  .packagesList[index]
                                                  .packageDescription
                                                  .isNotEmpty)
                                              ? Text(
                                                  invoiceModel
                                                      .packagesList[index]
                                                      .packageDescription,
                                                  style: pRegular14.copyWith(
                                                    fontSize: 12,
                                                    color:
                                                        CustomColor.black.value,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ],
                                      )),
                                      Padding(
                                        padding: EdgeInsets.only(top: 5.h),
                                        child: SizedBox(
                                          width: 80.w,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              showPrices
                                                  ? currencySymbol +
                                                      invoiceModel
                                                          .packagesList[index]
                                                          .packageTotal
                                                          .toStringAsFixed(2)
                                                  : "",
                                              style: pRegular14.copyWith(
                                                fontSize: 13,
                                                color: CustomColor.black.value,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5.h,
                                  ),
                                  DottedLine(
                                    direction: Axis.horizontal,
                                    lineLength: double.infinity,
                                    lineThickness: 1.0,
                                    dashLength: 1.0,
                                    dashColor:
                                        (themeController.isDarkMode.value)
                                            ? CustomColor.lightGray.value
                                            : CustomColor.darkGray.value,
                                    dashRadius: 50,
                                    dashGapLength: 2.0,
                                  )
                                ],
                              ),
                            );
                          }),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5.w),
                    child: Column(
                      children: [
                        discountData(
                          "SubTotal",
                          showPrices
                              ? currencySymbol +
                                  invoiceModel.subTotal.toStringAsFixed(2)
                              : "",
                        ),
                        SizedBox(height: 5.h),
                        discountData(
                          "Discount${invoiceModel.discountPercentageEnabled ? " (${invoiceModel.discountPer}%)" : ""}",
                          !showPrices
                              ? ""
                              : "$currencySymbol${invoiceModel.discountAmount}",
                        ),
                        SizedBox(height: 5.h),
                        if (invoiceModel.taxRatePer != 0.0)
                          discountData(
                            "Tax (${invoiceModel.taxRatePer}%)",
                            showPrices
                                ? "$currencySymbol${invoiceModel.taxAmount}"
                                : "",
                          ),
                        SizedBox(height: 5.h),
                        if (invoiceModel.convenienceFeeAmount > 0)
                          discountData(
                            "Convenience Fee (${invoiceModel.convenienceFeePercentage}%)",
                            showPrices
                                ? "$currencySymbol${invoiceModel.convenienceFeeAmount}"
                                : "",
                          ),
                        SizedBox(height: 5.h),
                        if (invoiceModel.isDepositPaid)
                          discountData(
                            "Deposit ${invoiceModel.isDepositPaid ? "(Paid) " : "(Unpaid) "}",
                            showPrices
                                ? "$currencySymbol${invoiceModel.depositAmount}"
                                : "",
                          ),
                        SizedBox(height: 5.h),
                        if (invoiceModel.estimateId.isNotEmpty &&
                            invoiceModel.depositAmount > 0)
                          Column(
                            children: [
                              discountData(
                                "Total Less Deposit",
                                showPrices
                                    ? "$currencySymbol${(invoiceModel.total - invoiceModel.depositAmount).toStringAsFixed(2)}"
                                    : "",
                              ),
                              SizedBox(height: 5.h),
                            ],
                          ),
                        discountData(
                          "Total",
                          showPrices
                              ? "$currencySymbol${(invoiceModel.total)}"
                              : "",
                          isDotted: false,
                        ),
                        SizedBox(
                          height: 15.h,
                        ),
                        Divider(
                          color: (themeController.isDarkMode.value)
                              ? CustomColor.lightGray.value
                              : CustomColor.darkGray.value,
                        ),
                      ],
                    ),
                  ),
                  if (invoiceModel.invoiceAcceptedPaymentMethods.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 20.h,
                        ),
                        Text(
                          "Accepted Payment Methods",
                          style: pBold16.copyWith(
                              fontSize: 16, color: CustomColor.black.value),
                        ),
                        SizedBox(
                          height: 10.h,
                        ),
                        Text(
                          invoiceModel.invoiceAcceptedPaymentMethods,
                          style: pRegular14.copyWith(
                              color: CustomColor.black.value),
                        ),
                      ],
                    ),
                  if (invoiceModel.invoicePaymentTerms.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 20.h,
                        ),
                        Text(
                          "Payment Terms",
                          style: pBold16.copyWith(
                              fontSize: 16, color: CustomColor.black.value),
                        ),
                        SizedBox(
                          height: 10.h,
                        ),
                        Text(
                          invoiceModel.invoicePaymentTerms,
                          style: pRegular14.copyWith(
                              color: CustomColor.black.value),
                        ),
                      ],
                    ),
                  if (invoiceModel.documents.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 20.h,
                        ),
                        Divider(
                          color: (themeController.isDarkMode.value)
                              ? CustomColor.lightGray.value
                              : CustomColor.darkGray.value,
                        ),
                        SizedBox(
                          height: 10.h,
                        ),
                        Text(
                          "Documents",
                          style: pBold16.copyWith(
                              fontSize: 16, color: CustomColor.black.value),
                        ),
                      ],
                    ),
                  if (invoiceModel.documents.isNotEmpty)
                    SizedBox(
                      height: 10.h,
                    ),
                  if (invoiceModel.documents.isNotEmpty)
                    GridView.builder(
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8),
                        shrinkWrap: true,
                        itemCount: invoiceModel.documents.length,
                        itemBuilder: (context, index) {
                          return InkWell(
                            onTap: () {
                              if (invoiceModel.documents[index].type ==
                                  AppConstant.file) {
                                Get.to(() => ImagePdfViewerClass(
                                      url: invoiceModel.documents[index].url,
                                    ));
                              } else {
                                Get.to(
                                  () => ImageNetworkScreen(
                                    url: invoiceModel.documents[index].url,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              color: CustomColor.lightGray.value,
                              height: 80.h,
                              width: 40.w,
                              child: (invoiceModel.documents[index].type ==
                                      AppConstant.image)
                                  ? Image.network(
                                      invoiceModel.documents[index].url,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(AssetsUtility.pdfIcon),
                            ),
                          );
                        }),
                  SizedBox(
                    height: 10.h,
                  ),
                  Text(
                    invoiceModel.clientMessage,
                    textAlign: TextAlign.center,
                    style: pRegular14.copyWith(color: CustomColor.black.value),
                  ),
                  SizedBox(
                    height: 100.h,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget discountData(String? name, String? val, {bool? isDotted = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: ResponsiveBuilder.isMobile(context) ? 100.w : 30.w,
              child: Text(
                name!,
                style: pRegular10.copyWith(
                    color: CustomColor.bgColor.value,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              width: ResponsiveBuilder.isMobile(context) ? 100.w : 30.w,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  val!,
                  style: pRegular10.copyWith(
                      color: CustomColor.bgColor.value,
                      fontSize: 13,
                      fontWeight:
                          (!isDotted!) ? FontWeight.bold : FontWeight.normal),
                ),
              ),
            ),
          ],
        ),
        (isDotted)
            ? Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: ResponsiveBuilder.isMobile(context) ? 200.w : 60.w,
                  child: DottedLine(
                    direction: Axis.horizontal,
                    lineLength: double.infinity,
                    lineThickness: 1.0,
                    dashLength: 1.0,
                    dashColor: (themeController.isDarkMode.value)
                        ? CustomColor.lightGray.value
                        : CustomColor.darkGray.value,
                    dashRadius: 50,
                    dashGapLength: 2.0,
                  ),
                ),
              )
            : Container()
      ],
    );
  }

  Widget button({IconData? iconData, Function? function, String? image}) {
    return InkWell(
      onTap: () {
        function!();
      },
      child: CircleAvatar(
        radius: 30,
        backgroundColor: CustomColor.darkGray.value,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
              child: Icon(
            iconData,
            color: CustomColor.darkBlue.value,
          )),
        ),
      ),
    );
  }
}
