import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:wash_iq/common/constant.dart';
import 'package:wash_iq/common/loader.dart';
import 'package:wash_iq/common/snackbar.dart';
import 'package:wash_iq/controllers/customers_controller.dart';
import 'package:wash_iq/controllers/email_automation_controller.dart';
import 'package:wash_iq/controllers/estimates_controller.dart';
import 'package:wash_iq/controllers/new_auth_controller.dart';
import 'package:wash_iq/model/company_model.dart';
import 'package:wash_iq/model/customer_model.dart';
import 'package:wash_iq/model/invoice_model.dart';
import 'package:wash_iq/model/invoice_package_model.dart';
import 'package:wash_iq/model/public_invoice_model.dart';
import 'package:wash_iq/view/generate_pdfs/invoice_generate_pdf_screen.dart';

import '../model/attachment_model.dart';
import '../model/estimate_model.dart';
import '../model/invoice_service_model.dart';
import '../model/totals_model.dart';
import '../services/cache_storage/cache_storage.dart';
import '../view/generate_pdfs/estimate_generate_pdf_screen.dart';
import 'company_profile_controller.dart';
import 'dashboard_controller.dart';
import 'firebase_storage_controller.dart';
import 'my_price_controller.dart';

class InvoiceController extends GetxController {
  CustomerController addCustomerController = Get.put(CustomerController());
  EstimatesController estimatesController = Get.put(EstimatesController());
  MyPriceController priceController = Get.put(MyPriceController());
  NewAuthController authController = Get.find();
  CompanyProfileController companyProfileController = Get.find();
  EmailAutomationController emailAutomationController =
      Get.put(EmailAutomationController());
  final FirebaseStorageController firebaseStorageController = Get.find();
  var searchController = TextEditingController().obs;
  final FirebaseFirestore fireStore = FirebaseFirestore.instance;
  RxList<String> invoiceScreensUserPermissions = <String>[].obs;
  RxString paymentUrl = "".obs;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      invoicesStreamSubscription;
  RxString sortingOption = AppConstant.invoiceDateSortingOption.obs;
  RxString sortingCondition = AppConstant.descending.obs;
  RxBool isDataAvailable = false.obs;
  RxBool isPendingData = false.obs;
  RxBool isPaidData = false.obs;
  FirebaseStorage firebaseStorage = FirebaseStorage.instance;
  DocumentSnapshot? lastCustomerInvoicesDocument;
  final List<String> paymentTermList = [
    "Due Upon Receipt",
    "1% 10 Net 30",
    "30 days",
  ];
  final List<String> paymentStatusList = [
    AppConstant.paid,
    AppConstant.pending,
  ];
  final List<String> sortingOptionsList = [
    AppConstant.invoiceDateSortingOption,
    AppConstant.invoiceNumberSortingOption,
  ];
  final List<String> sortingConditionsList = [
    AppConstant.ascending,
    AppConstant.descending,
  ];
  RxList<InvoiceModel> invoiceList = <InvoiceModel>[].obs;
  RxList<InvoiceModel> invoiceSearchList = <InvoiceModel>[].obs;

  Rx<InvoiceModel> currentInvoiceModel = InvoiceModel.empty().obs;
  Rx<CustomerModel> currentCustomerModel = CustomerModel.empty().obs;
  EstimateModel currentInvoiceEstimateModel = EstimateModel.empty();
  int lastInvoiceNo = 0;

  void getInvoiceAttachment(
      {required ImageSource imageSource, bool file = false}) async {
    var attachments = await firebaseStorageController.getAttachments(
      imageSource: imageSource,
      file: file,
    );
    if (attachments.isNotEmpty) {
      currentInvoiceModel.value.documents.addAll(attachments);
      currentInvoiceModel.refresh();
      Get.back();
    }
  }

  void deleteInvoiceAttachment(int index) {
    currentInvoiceModel.value.documents.removeAt(index);
    currentInvoiceModel.refresh();
  }

  checkInvoiceUserPermissions({required String permission}) {
    invoiceScreensUserPermissions.value =
        authController.checkScreenUserPermission(AppConstant.invoicesScreen);
    return invoiceScreensUserPermissions.contains(permission);
  }

  Future<List<InvoiceModel>> getCustomerInvoices({
    required String customerId,
    required bool moreData,
    required bool viewPrices,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    List<InvoiceModel> invoices = [];
    if (!moreData) {
      lastCustomerInvoicesDocument = null;
    }
    QuerySnapshot<Map<String, dynamic>> query = !moreData
        ? await fireStore
            .collection(AppConstant.userMaster)
            .doc(userId)
            .collection(AppConstant.companyProfileMaster)
            .doc(companyId)
            .collection(AppConstant.invoiceMaster)
            .where(AppConstant.customerId, isEqualTo: customerId)
            .orderBy(AppConstant.invoiceDate, descending: true)
            .limit(10)
            .get()
        : await fireStore
            .collection(AppConstant.userMaster)
            .doc(userId)
            .collection(AppConstant.companyProfileMaster)
            .doc(companyId)
            .collection(AppConstant.invoiceMaster)
            .where(AppConstant.customerId, isEqualTo: customerId)
            .orderBy(AppConstant.invoiceDate, descending: true)
            .startAfterDocument(lastCustomerInvoicesDocument!)
            .limit(10)
            .get();
    invoices = query.docs.map((e) {
      var data = e.data();
      data[AppConstant.docId] = e.id;
      return InvoiceModel.fromMap(
        data: data,
        includePrices: viewPrices,
      );
    }).toList();
    if (query.docs.isNotEmpty) {
      lastCustomerInvoicesDocument = query.docs.last;
    }
    return invoices;
  }

  addPublicInvoiceData({
    required String invId,
    required String customerPhone,
    required String customerPhoneCountryCode,
    required String customerEmail,
    required String customerCompanyName,
    required String stripeLink,
    required Uint8List invoicePdfFileBytes,
    required Uint8List estimatePdfFileBytes,
    required bool isQuickInvoice,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    InvoiceModel? invoiceModel;
    EstimateModel? estimateModel;
    CompanyModel companyModel =
        estimatesController.companyFormController.companyInfo.value;

    int invoiceIndex =
        invoiceList.indexWhere((element) => element.docId == invId);
    if (invoiceIndex == -1) {
      await getInvoiceById(
        invId: invId,
        setAsCurrentInvoice: false,
      );
      invoiceIndex =
          invoiceList.indexWhere((element) => element.docId == invId);
    }
    if (invoiceIndex != -1) {
      invoiceModel = invoiceList[invoiceIndex];
    } else {
      if (!isQuickInvoice) {
        int estIndex = estimatesController.estimateList
            .indexWhere((element) => element.docId == invId);
        if (estIndex == -1) {
          await estimatesController.getEstimateById(
            estId: invId,
            includeEstimatePrices: true,
          );
          estIndex = estimatesController.estimateList
              .indexWhere((element) => element.docId == invId);
        }
        if (estIndex != -1) {
          estimateModel = estimatesController.estimateList[estIndex];
        }
      }
    }
    String value = companyModel.email.split("@").first;
    String invoicePdfUrl = "";
    String estimatePdfUrl = "";
    Reference refer;
    if (invoiceModel != null || estimateModel != null) {
      if (invoiceModel != null) {
        if (invoicePdfFileBytes.isNotEmpty) {
          refer = firebaseStorage
              .ref(value)
              .child("Invoice")
              .child("pdf")
              .child(invoiceModel.docId);
          await refer.putData(
            invoicePdfFileBytes,
            SettableMetadata(contentType: 'application/pdf'),
          );
          invoicePdfUrl = await refer.getDownloadURL();
          updateInvoicePdfLink(invId: invId, url: invoicePdfUrl);
        } else {
          invoicePdfUrl = invoiceModel.invoicePdfUrl;
        }
      }
      if (estimateModel != null) {
        if (estimatePdfUrl.isEmpty) {
          estimatePdfUrl = estimateModel.estimatePdfUrl;
        }
      }

      PublicInvoiceModel publicInvoiceModel = PublicInvoiceModel(
        id: invoiceModel?.docId ?? estimateModel!.docId,
        userId: userId,
        companyId: companyId,
        status: "",
        invoiceNumber: invoiceModel?.invoiceNumber ?? -1,
        invoiceDate: invoiceModel?.invoiceDate ?? "",
        paymentTerm: invoiceModel?.paymentTerm ?? "",
        discountPer: invoiceModel?.discountPer.toStringAsFixed(2) ??
            estimateModel!.discountPer.toStringAsFixed(2),
        taxRatePer: invoiceModel?.taxRatePer.toStringAsFixed(2) ??
            estimateModel!.taxPer.toStringAsFixed(2),
        clientMessage: invoiceModel?.clientMessage ?? "",
        paymentStatus: invoiceModel?.paymentStatus ?? AppConstant.pending,
        subTotal: invoiceModel?.subTotal.toStringAsFixed(2) ??
            estimateModel!.subTotal.toStringAsFixed(2),
        taxAmount: invoiceModel?.taxAmount.toStringAsFixed(2) ??
            estimateModel!.taxAmount.toStringAsFixed(2),
        discountAmount: invoiceModel?.discountAmount.toStringAsFixed(2) ??
            estimateModel!.discountAmount.toStringAsFixed(2),
        convenienceFeePercentage:
            invoiceModel?.convenienceFeePercentage.toStringAsFixed(2) ?? '0.0',
        convenienceFeeAmount:
            invoiceModel?.convenienceFeeAmount.toStringAsFixed(2) ?? '0.0',
        stripeMerchantId: companyModel.stripeMerchantId,
        companyAddress: companyModel.address,
        companyEmail: companyModel.email,
        companyName: companyModel.companyName,
        companyPhone: "+${companyModel.countryCode}${companyModel.phoneNumber}",
        companyPhoto: companyModel.image,
        customerPhone: "+$customerPhoneCountryCode$customerPhone",
        customerAddress: invoiceModel?.address ?? estimateModel!.address,
        customerName: invoiceModel?.customerName ?? estimateModel!.customerName,
        customerEmail: customerEmail,
        customerCompanyName: customerCompanyName,
        invoiceDocuments: invoiceModel?.documents ?? [],
        estimateDocuments: estimateModel?.documents ?? [],
        estimateBottomImageDescriptions:
            estimateModel?.bottomPhotoDescriptions ?? [],
        estimateBottomImageUrls: estimateModel?.bottomPhotos ?? [],
        estimateId: invoiceModel?.estimateId ?? estimateModel!.docId,
        estimateNo: estimateModel?.estimateNo ?? "",
        estimateType: invoiceModel?.estimateType ?? estimateModel!.estimateType,
        total: invoiceModel?.total.toStringAsFixed(2) ??
            estimateModel!.total.toStringAsFixed(2),
        depositPercentage: invoiceModel?.depositPercentage.toStringAsFixed(2) ??
            estimateModel!.depositPercentage.toStringAsFixed(2),
        depositAmount: invoiceModel?.depositAmount.toStringAsFixed(2) ??
            estimateModel!.depositAmount.toStringAsFixed(2),
        isDepositPaid:
            invoiceModel?.isDepositPaid ?? estimateModel!.isDepositPaid,
        currencyName: companyModel.currencyName,
        currencySymbol: companyModel.currencySymbol,
        serviceList: invoiceModel?.serviceList ??
            estimateModel!.servicesList
                .map((e) => InvoiceService(
                      total: e.serviceTotal.toStringAsFixed(2),
                      serviceDescription: e.serviceDescription,
                      serviceName: e.serviceName,
                      serviceImageUrl: e.image,
                      serviceId: e.serviceId,
                      lengthOfService: e.lengthOfService,
                      onlineSelfSchedule: e.onlineSelfSchedule,
                      customServiceImageUrl: e.customServiceImageUrl,
                    ))
                .toList(),
        packagesList: invoiceModel?.packagesList ??
            estimateModel!.packagesList
                .map((e) => InvoicePackageModel(
                      packageId: e.packageId,
                      packagePrice: e.packagePrice,
                      packageQuantity: e.packageQuantity,
                      packageTotal: e.packageTotal,
                      packageDescription: e.packageDescription,
                      packageName: e.packageName,
                      favorite: e.favorite,
                      packageImageUrl: e.networkImage,
                    ))
                .toList(),
        stripeLink: stripeLink,
        invoicePdfUrl: invoicePdfUrl,
        estimatePdfUrl: estimatePdfUrl,
        estimateFooterTitle:
            estimatesController.footerTitleController.value.text,
        estimateFooterDescription:
            estimatesController.footerDescriptionController.value.text,
        estimateTermsConditions:
            estimatesController.estimateTermsConditionsUrl.value,
        invoicePaymentTerms:
            invoiceModel != null && invoiceModel.invoicePaymentTerms.isNotEmpty
                ? invoiceModel.invoicePaymentTerms
                : companyModel.invoicePaymentTerms,
        invoiceAcceptedPaymentMethods: invoiceModel != null &&
                invoiceModel.invoiceAcceptedPaymentMethods.isNotEmpty
            ? invoiceModel.invoiceAcceptedPaymentMethods
            : companyModel.invoiceAcceptedPaymentMethods,
        stripeActiveSubscriptionId:
            invoiceModel?.stripeActiveSubscriptionId ?? "",
        stripeScheduleSubscriptionId:
            invoiceModel?.stripeScheduleSubscriptionId ?? "",
        stripePriceId: invoiceModel?.stripePriceId ?? "",
        stripeCustomerId: invoiceModel?.stripeCustomerId ?? "",
        stripeSubscriptionIntervalName:
            invoiceModel?.stripeSubscriptionIntervalName ?? "",
        stripeSubscriptionIntervalCount:
            invoiceModel?.stripeSubscriptionIntervalCount ?? 0,
        recurringInvoiceStartDateTimestamp:
            invoiceModel?.recurringInvoiceStartDateTimestamp ?? 0,
        recurringInvoiceEndDateTimestamp:
            invoiceModel?.recurringInvoiceEndDateTimestamp ?? 0,
        isRecurringInvoice: invoiceModel?.isRecurring ?? false,
        recurringInvoicePaymentLinksHistory:
            invoiceModel?.recurringInvoicePaymentLinksHistory ?? [],
        recurringInvoicesData: invoiceModel?.recurringInvoicesData ?? [],
        discountPercentageEnabled: invoiceModel?.discountPercentageEnabled ??
            estimateModel!.discountPercentageEnabled,
        depositPercentageEnabled: invoiceModel?.depositPercentageEnabled ??
            estimateModel!.depositPercentageEnabled,
        onlineSelfSchedule: estimateModel?.onlineSelfSchedule ?? false,
      );
      await fireStore
          .collection(AppConstant.publicInvoices)
          .doc(publicInvoiceModel.id)
          .set(publicInvoiceModel.toMap());

      if (estimateModel != null) {
        if (estimatePdfFileBytes.isNotEmpty) {
          refer = firebaseStorage
              .ref(value)
              .child("Estimate")
              .child("pdf")
              .child(estimateModel.docId);
          await refer.putData(
            estimatePdfFileBytes,
            SettableMetadata(contentType: 'application/pdf'),
          );
          estimatePdfUrl = await refer.getDownloadURL();
          estimatesController.updateEstimatePdfLink(
            estId: estimateModel.docId,
            url: estimatePdfUrl,
          );
        }
      }
    }
  }

  getLastInvoiceNo() async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    var data = await fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .orderBy(AppConstant.invoiceNumber, descending: true)
        .limit(1)
        .get();
    if (data.docs.isEmpty) {
      lastInvoiceNo = 0;
    } else {
      try {
        lastInvoiceNo =
            int.parse(data.docs.first.data()[AppConstant.invoiceNumber]);
      } catch (e) {
        lastInvoiceNo = data.docs.first.data()[AppConstant.invoiceNumber];
      }
    }
  }

  Future<DocumentReference<Map<String, dynamic>>>
      createNewQuickInvoiceFirestoreDocument() async {
    Loader.showLoader();
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    var ref = fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .doc();
    Loader.hideLoader();
    return ref;
  }

  markRecurringInvoiceAsPaidInsideMainReferenceInvoice(
      InvoiceModel model) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    if (model.recurrenceMainReferenceInvoiceDocId.isNotEmpty) {
      int index = invoiceList.indexWhere((element) =>
          element.docId == model.recurrenceMainReferenceInvoiceDocId);
      if (index == -1) {
        await getInvoiceById(
          invId: model.recurrenceMainReferenceInvoiceDocId,
          setAsCurrentInvoice: false,
        );
        index = invoiceList.indexWhere((element) =>
            element.docId == model.recurrenceMainReferenceInvoiceDocId);
      }
      if (index != -1) {
        for (var element in invoiceList[index].recurringInvoicesData) {
          if (element.newDocId == model.docId) {
            element.paidAt = Timestamp.now().millisecondsSinceEpoch;
          }
        }
        invoiceList[index].updatedAt = Timestamp.now().millisecondsSinceEpoch;
        invoiceList[index].invoicePdfGenerationStatus = AppConstant.processing;
        invoiceList[index].invoicePdfUrl = "";
        await fireStore
            .collection(AppConstant.userMaster)
            .doc(userId)
            .collection(AppConstant.companyProfileMaster)
            .doc(companyId)
            .collection(AppConstant.invoiceMaster)
            .doc(model.recurrenceMainReferenceInvoiceDocId)
            .update(invoiceList[index].toMap());
      }
    }
  }

  markRecurringInvoiceDocumentsAsPaid({
    required InvoiceModel model,
    required int paidAtTimestamp,
    required bool isQuickInvoice,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    for (int i = 0; i < model.recurringInvoicesData.length; i++) {
      if (model.recurringInvoicesData[i].paidAt == 0 ||
          model.recurringInvoicesData[i].paidAt == paidAtTimestamp) {
        var doc = await fireStore
            .collection(AppConstant.userMaster)
            .doc(userId)
            .collection(AppConstant.companyProfileMaster)
            .doc(companyId)
            .collection(AppConstant.invoiceMaster)
            .doc(model.recurringInvoicesData[i].newDocId)
            .get();
        if (doc.exists) {
          doc.reference.update({
            AppConstant.paymentStatus: "Paid",
            AppConstant.paidAt: Timestamp.now().millisecondsSinceEpoch,
          });
          List<InvoiceService> servicesList = doc
                  .data()?[AppConstant.serviceList]
                  .map<InvoiceService>((e) => InvoiceService.fromMap(
                        data: e,
                        includePrices: true,
                      ))
                  .toList() ??
              [];
          increaseInvoiceTotal(
            services: servicesList,
            discountPercentage: model.discountPer,
            taxPercentage: model.taxRatePer,
            isQuickInvoice: isQuickInvoice,
            invoiceTotal: model.total,
          );
        }
      }
    }
  }

  deleteRecurringInvoiceDataFromMainReference({
    required String recurringInvoiceId,
    required String recurringInvoiceStripeUrl,
    required String mainReferenceId,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    int index =
        invoiceList.indexWhere((element) => element.docId == mainReferenceId);
    if (index == -1) {
      await getInvoiceById(
        invId: mainReferenceId,
        setAsCurrentInvoice: false,
      );
      index =
          invoiceList.indexWhere((element) => element.docId == mainReferenceId);
    }
    if (index != -1) {
      invoiceList[index]
          .recurringInvoicesData
          .removeWhere((element) => element.newDocId == recurringInvoiceId);
      invoiceList[index].recurringInvoicePaymentLinksHistory.removeWhere(
          (element) => element.containsKey(recurringInvoiceStripeUrl));
      await fireStore
          .collection(AppConstant.userMaster)
          .doc(userId)
          .collection(AppConstant.companyProfileMaster)
          .doc(companyId)
          .collection(AppConstant.invoiceMaster)
          .doc(mainReferenceId)
          .update({
        AppConstant.recurringInvoicesData: invoiceList[index]
            .recurringInvoicesData
            .map((e) => e.toMap())
            .toList(),
        AppConstant.recurringInvoicePaymentLinksHistory:
            invoiceList[index].recurringInvoicePaymentLinksHistory,
      });
    }
  }

  deleteRecurringInvoiceDocuments({
    required InvoiceModel model,
    required bool isQuickInvoice,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    for (int i = 0; i < model.recurringInvoicesData.length; i++) {
      var doc = await fireStore
          .collection(AppConstant.userMaster)
          .doc(userId)
          .collection(AppConstant.companyProfileMaster)
          .doc(companyId)
          .collection(AppConstant.invoiceMaster)
          .doc(model.recurringInvoicesData[i].newDocId)
          .get();
      if (doc.exists) {
        String invoiceDate = doc.data()?[AppConstant.invoiceDate];
        List<InvoiceService> servicesList = doc
                .data()?[AppConstant.serviceList]
                .map<InvoiceService>((e) => InvoiceService.fromMap(
                      data: e,
                      includePrices: true,
                    ))
                .toList() ??
            [];
        String discount = doc.data()?[AppConstant.discountPer] ?? "0.0";
        String taxRate = doc.data()?[AppConstant.taxRatePer] ?? "0.0";
        String invId = doc.id;
        await doc.reference.delete();
        invoiceList.removeWhere((element) => element.docId == invId);
        invoiceSearchList.removeWhere((element) => element.docId == invId);
        await decreaseInvoiceTotal(
          services: servicesList,
          discountPercentage: double.tryParse(discount) ?? 0.0,
          taxPercentage: double.tryParse(taxRate) ?? 0.0,
          isQuickInvoice: isQuickInvoice,
          invoiceDate: invoiceDate,
          invoiceTotal: double.parse(doc.data()?[AppConstant.total] ?? "0.0"),
        );
      }
    }
  }

  deletePhoto(String? filePath) async {
    try {
      await FirebaseStorage.instance.ref().child(filePath!).delete();
    } catch (e) {
      log("Error deletePhoto() =>$e");
    }
  }

  confirmPaid({
    required int index,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    final DateFormat formatter = DateFormat('MM/dd/yyyy');
    final String formatted = formatter.format(DateTime.now());
    InvoiceModel invoiceModel = InvoiceModel.empty();
    var estimateModel = estimatesController.estimateList[index];
    var customerModel =
        await addCustomerController.getCustomerIdInfo(estimateModel.customerId);
    Loader.showLoader();

    await estimatesController.markEstimateAsPaid(
      estId: estimateModel.docId,
    );
    if (estimateModel.invoiceId.isNotEmpty) {
      await markInvoiceAsPaid(
        invId: estimateModel.invoiceId,
        isEstimateInvoice: true,
        markEstimateAsPaid: false,
      );
    } else {
      await createInvoiceFromEstimate(
        estimateModel: EstimateModel.fromMap(
          data: estimateModel.toMap(),
          includePrices: true,
        ),
        customerModel: customerModel,
        isPaid: true,
      );
    }

    int invoiceIndex = invoiceList
        .indexWhere((element) => element.estimateId == estimateModel.docId);
    if (invoiceIndex != -1) {
      invoiceModel = invoiceList[invoiceIndex];
    } else {
      await getInvoiceById(
        invId: estimateModel.docId,
        setAsCurrentInvoice: false,
      );
      invoiceIndex = invoiceList
          .indexWhere((element) => element.estimateId == estimateModel.docId);
      if (invoiceIndex != -1) {
        invoiceModel = invoiceList[invoiceIndex];
      }
    }

    Loader.hideLoader();
    Map invoiceCustomerDataMap = {
      AppConstant.customerName: estimateModel.customerName,
      AppConstant.email: customerModel.email,
      AppConstant.address: estimateModel.address,
      AppConstant.customerCompanyName: customerModel.companyName,
      AppConstant.date: formatted,
      AppConstant.paymentTerm: "Due Upon Receipt",
      AppConstant.invoiceNumber: invoiceModel.invoiceNumber,
    };

    Uint8List invoiceFileBytes = await invoiceGeneratePdf(
      userId: userId,
      companyProfileController: estimatesController.companyFormController,
      invoiceController: this,
      customerData: invoiceCustomerDataMap,
      invoiceNumber: invoiceModel.invoiceNumber,
      invoiceServicesList: invoiceModel.serviceList,
      invoicePackagesList: invoiceModel.packagesList,
      subTotal: invoiceModel.subTotal.toStringAsFixed(2),
      discountRate: invoiceModel.discountPer.toStringAsFixed(2),
      discountAmount: invoiceModel.discountAmount.toStringAsFixed(2),
      taxRate: invoiceModel.taxRatePer.toStringAsFixed(2),
      taxAmount: invoiceModel.taxAmount.toStringAsFixed(2),
      netTotalInvoice: invoiceModel.total.toStringAsFixed(2),
      paymentStatus: "Paid",
      depositAmount: invoiceModel.depositAmount.toString(),
      depositPercentage: invoiceModel.depositPercentage.toStringAsFixed(2),
      isDepositPaid: invoiceModel.isDepositPaid,
      totalLessDeposit:
          (invoiceModel.total - invoiceModel.depositAmount).toStringAsFixed(2),
      isQuickInvoice: false,
      acceptedPaymentMethods: invoiceModel.invoiceAcceptedPaymentMethods,
      paymentTerms: invoiceModel.invoicePaymentTerms,
      estimateID: estimateModel.docId,
      invoiceId: estimateModel.invoiceId,
      documentList: invoiceModel.documents,
      clientMessage: invoiceModel.clientMessage,
      generatePaymentLink: !invoiceModel.isRecurring,
      convenienceFeeAmount:
          invoiceModel.convenienceFeeAmount.toStringAsFixed(2),
      invoiceModel: invoiceModel,
    );
    var estimateCustomerDataMap = {
      AppConstant.customerName: estimateModel.customerName,
      AppConstant.email: customerModel.email,
      AppConstant.customerCompanyName: customerModel.companyName,
      AppConstant.address: estimateModel.address,
      AppConstant.date: estimateModel.createdDate,
      AppConstant.estimateNo: estimateModel.estimateNo,
    };
    Uint8List estimateFileBytes = await estimateGeneratePdf(
      companyProfileController: estimatesController.companyFormController,
      documentList: estimateModel.documents,
      customerData: estimateCustomerDataMap,
      discountAmount: estimateModel.discountAmount,
      taxAmount: estimateModel.taxAmount,
      total: estimateModel.total,
      subTotal: estimateModel.subTotal,
      bottomImageUrls: estimateModel.bottomPhotos,
      bottomImageDescriptions: estimateModel.bottomPhotoDescriptions,
      estimateServicesList: estimateModel.servicesList
          .map(
            (e) => InvoiceService(
              total: e.serviceTotal.toStringAsFixed(2),
              serviceDescription: e.serviceDescription,
              serviceName: e.serviceName,
              serviceImageUrl: e.image,
              customServiceImageUrl: e.customServiceImageUrl,
              serviceId: e.serviceId,
              lengthOfService: e.lengthOfService,
              onlineSelfSchedule: e.onlineSelfSchedule,
            ),
          )
          .toList(),
      estimatePackagesList: estimateModel.packagesList,
      netTotalEstimate: estimateModel.total,
    );
    await addPublicInvoiceData(
      invId: invoiceModel.docId,
      customerPhone: customerModel.phoneNumber,
      customerPhoneCountryCode: customerModel.countryCode.toString(),
      customerEmail: customerModel.email,
      customerCompanyName: customerModel.companyName,
      stripeLink: paymentUrl.value,
      invoicePdfFileBytes: invoiceFileBytes,
      estimatePdfFileBytes: estimateFileBytes,
      isQuickInvoice: false,
    );
  }

  addEstimateData({
    required String estId,
    required List<InvoiceService> servicesList,
  }) async {
    Loader.showLoader();
    List<InvoiceService> estimateServicesList = [];
    CustomerModel customerDataModel;
    String userId = CacheStorageService.instance.read(AppConstant.userId);

    bool isRecurring = false;
    bool invoiceUpdated = false;
    bool hasInvoice = false;

    int estimateIndex = estimatesController.estimateList
        .indexWhere((element) => element.docId == estId);
    if (estimateIndex == -1) {
      await estimatesController.getEstimateById(
        estId: estId,
        includeEstimatePrices: true,
      );
      estimateIndex = estimatesController.estimateList
          .indexWhere((element) => element.docId == estId);
    }
    var estimateModel = estimatesController.estimateList[estimateIndex];
    hasInvoice = estimateModel.invoiceStatus;
    customerDataModel =
        await addCustomerController.getCustomerIdInfo(estimateModel.customerId);
    final DateFormat formatter = DateFormat('MM/dd/yyyy');
    final String formatted = formatter.format(DateTime.now());

    for (var element in servicesList) {
      estimateServicesList.add(InvoiceService.fromMap(
        data: element.toMap(),
        includePrices: true,
      ));
    }

    int invoiceIndex = invoiceList
        .indexWhere((element) => element.estimateId == estimateModel.docId);
    if (invoiceIndex == -1) {
      await getInvoiceById(
        invId: estimateModel.docId,
        setAsCurrentInvoice: false,
      );
      invoiceIndex = invoiceList
          .indexWhere((element) => element.estimateId == estimateModel.docId);
    }
    if (invoiceIndex != -1) {
      hasInvoice = true;
      isRecurring = invoiceList[invoiceIndex].isRecurring;
      if (invoiceList[invoiceIndex].updatedAt > 0) {
        invoiceUpdated = true;
      }
    }
    if (!invoiceUpdated && !isRecurring && hasInvoice) {
      setInvoiceDataForCreateEstimate(
        estimateModel: estimateModel,
        customerModel: customerDataModel,
        calculateConvenienceFee: false,
      );
      currentInvoiceModel.value.docId = estimateModel.docId;
      currentInvoiceModel.value.invoiceNumber =
          invoiceList[invoiceIndex].invoiceNumber;
      await saveInvoiceData(
        isEdit: true,
        isEstimateInvoice: true,
      );
      if (!isDataAvailable.value) {
        int index = invoiceList
            .indexWhere((element) => element.docId == estimateModel.docId);
        if (index != -1) {
          invoiceList[index] = InvoiceModel.fromMap(
            data: currentInvoiceModel.value.toMap(),
            includePrices: true,
          );
        }
      }
    }
    Loader.hideLoader();
    log("Hideeeee");
    Uint8List invoiceFileBytes = Uint8List(0);
    if (!invoiceUpdated && !isRecurring && hasInvoice) {
      Map invoiceCustomerDataMap = {
        AppConstant.customerName: estimateModel.customerName,
        AppConstant.email: customerDataModel.email,
        AppConstant.address: estimateModel.address,
        AppConstant.customerCompanyName: customerDataModel.companyName,
        AppConstant.date: formatted,
        AppConstant.paymentTerm: "Due Upon Receipt",
        AppConstant.invoiceNumber: currentInvoiceModel.value.invoiceNumber,
      };
      debugPrint("invoiceCustomerDataMap ${estimateModel.toMap()}");
      debugPrint(">>> total ${estimateModel.total}");
      double totalLessDeposit =
          estimateModel.total - estimateModel.depositAmount;
      invoiceFileBytes = await invoiceGeneratePdf(
        userId: userId,
        companyProfileController: estimatesController.companyFormController,
        invoiceController: this,
        customerData: invoiceCustomerDataMap,
        invoiceNumber: currentInvoiceModel.value.invoiceNumber,
        invoiceServicesList: estimateServicesList,
        invoicePackagesList: estimatesController.estimateActivePackagesList
            .map((element) => InvoicePackageModel.fromMap(
                  data: element.toMap(),
                  includePrices: true,
                ))
            .toList(),
        subTotal: estimateModel.subTotal.toStringAsFixed(2),
        discountRate: estimateModel.discountPer.toStringAsFixed(2),
        discountAmount: estimateModel.discountAmount.toStringAsFixed(2),
        taxRate: estimateModel.taxPer.toStringAsFixed(2),
        taxAmount: estimateModel.taxAmount.toStringAsFixed(2),
        netTotalInvoice: estimateModel.total.toStringAsFixed(2),
        depositAmount: estimateModel.depositAmount.toString(),
        depositPercentage: estimateModel.depositPercentage.toString(),
        isDepositPaid: estimateModel.isDepositPaid,
        totalLessDeposit: totalLessDeposit.toString(),
        paymentStatus: "Pending",
        isQuickInvoice: false,
        acceptedPaymentMethods: "Search",
        paymentTerms: "Search",
        estimateID: estimateModel.docId,
        invoiceId: estimateModel.invoiceId,
        documentList: [], //estimatesController.estimateList[estimateIndex].documents,
        clientMessage: "",
        convenienceFeeAmount: "0.00",
        invoiceModel: currentInvoiceModel.value,
      );
    }
    var estimateCustomerDataMap = {
      AppConstant.customerName: estimateModel.customerName,
      AppConstant.email: customerDataModel.email,
      AppConstant.customerCompanyName: customerDataModel.companyName,
      AppConstant.address: estimateModel.address,
      AppConstant.date: estimateModel.createdDate,
      AppConstant.estimateNo: estimateModel.estimateNo,
    };
    Uint8List estimateFileBytes = await estimateGeneratePdf(
      companyProfileController: estimatesController.companyFormController,
      documentList: estimateModel.documents,
      customerData: estimateCustomerDataMap,
      discountAmount: estimateModel.discountAmount,
      taxAmount: estimateModel.taxAmount,
      total: estimateModel.total,
      subTotal: estimateModel.subTotal,
      bottomImageUrls: estimateModel.bottomPhotos,
      bottomImageDescriptions: estimatesController
          .estimateList[estimateIndex].bottomPhotoDescriptions,
      estimateServicesList: estimateServicesList,
      estimatePackagesList: estimatesController.estimateActivePackagesList,
      netTotalEstimate: estimateModel.total,
    );
    await addPublicInvoiceData(
      invId: estId,
      customerPhone: customerDataModel.phoneNumber,
      customerPhoneCountryCode: customerDataModel.countryCode.toString(),
      customerEmail: customerDataModel.email,
      customerCompanyName: customerDataModel.companyName,
      stripeLink: paymentUrl.value,
      invoicePdfFileBytes: invoiceFileBytes,
      estimatePdfFileBytes: estimateFileBytes,
      isQuickInvoice: false,
    );
  }

  updateInvoicePdfLink({required String invId, required String url}) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    await fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .doc(invId)
        .update({AppConstant.invoicePdfUrl: url});
    int index = invoiceList.indexWhere((element) => element.docId == invId);
    if (index != -1) {
      invoiceList[index].invoicePdfUrl = url;
      invoiceList.refresh();
    }
    index = invoiceSearchList.indexWhere((element) => element.docId == invId);
    if (index != -1) {
      invoiceSearchList[index].invoicePdfUrl = url;
      invoiceSearchList.refresh();
    }
  }

  getInvoiceData({
    required String userId,
    required bool hasData,
    required bool includePrices,
    VoidCallback? afterSorting,
  }) async {
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    resetSortingParameters();
    var snapshots = fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .orderBy(AppConstant.invoiceDate, descending: true)
        .snapshots();

    if (!hasData) {
      isPendingData.value = false;
      isPaidData.value = false;
      invoiceList.clear();
      invoiceSearchList.clear();
      await addCustomerController.getCustomersData();
    }

    debugPrint("Invoice Data Fetched");
    invoicesStreamSubscription = snapshots.listen((event) {
      for (var document in event.docChanges) {
        if (document.doc.data() != null) {
          var doc = document.doc.data()!;
          doc[AppConstant.docId] = document.doc.id;
          int index = invoiceList
              .indexWhere((invoice) => invoice.docId == document.doc.id);
          if (index != -1) {
            debugPrint(doc[AppConstant.invoiceNumber].toString());
            invoiceList[index] = InvoiceModel.fromMap(
              data: doc,
              includePrices: includePrices,
            );
            index = invoiceSearchList
                .indexWhere((invoice) => invoice.docId == document.doc.id);
            if (index != -1) {
              invoiceSearchList[index] = InvoiceModel.fromMap(
                data: doc,
                includePrices: includePrices,
              );
            }
          } else {
            try {
              invoiceList.add(InvoiceModel.fromMap(
                data: doc,
                includePrices: includePrices,
              ));
              invoiceSearchList.add(InvoiceModel.fromMap(
                data: doc,
                includePrices: includePrices,
              ));
            } catch (e) {
              debugPrint("docId: ${document.doc.id}");
              debugPrint("Error#4445: $e");
            }
          }
          if (doc[AppConstant.paymentStatus] == "Pending") {
            isPendingData.value = true;
          } else if (doc[AppConstant.paymentStatus] == "Paid") {
            isPaidData.value = true;
          }
        }
      }
      invoiceList.value = invoiceList.toSet().toList();
      invoiceSearchList.value = invoiceSearchList.toSet().toList();
      sortInvoiceList();
      if (invoiceList.isNotEmpty) {
        getLastInvoiceNoFromList();
      }
      // getLatestInvoicesForDashboard();
      if (afterSorting != null) {
        afterSorting();
      }
      isDataAvailable.value = true;
    });
  }

  getLastInvoiceNoFromList() {
    lastInvoiceNo = invoiceList
        .reduce((curr, next) =>
            curr.invoiceNumber > next.invoiceNumber ? curr : next)
        .invoiceNumber;
  }

  sortInvoiceList() {
    if (sortingOption.value == AppConstant.invoiceDateSortingOption) {
      invoiceList.sort((a, b) {
        var dateFormattedA = DateFormat("MM/dd/yyyy").parse(a.invoiceDate);
        var dateFormattedB = DateFormat("MM/dd/yyyy").parse(b.invoiceDate);
        var ascSortingCondition = (dateFormattedA.millisecondsSinceEpoch -
                dateFormattedB.millisecondsSinceEpoch) +
            (a.invoiceNumber - b.invoiceNumber);
        var descSortingCondition = (dateFormattedB.millisecondsSinceEpoch -
                dateFormattedA.millisecondsSinceEpoch) +
            (b.invoiceNumber - a.invoiceNumber);
        return sortingCondition.value == AppConstant.descending
            ? descSortingCondition
            : ascSortingCondition;
      });
      invoiceSearchList.sort((a, b) {
        var dateFormattedA = DateFormat("MM/dd/yyyy").parse(a.invoiceDate);
        var dateFormattedB = DateFormat("MM/dd/yyyy").parse(b.invoiceDate);
        var ascSortingCondition = (dateFormattedA.millisecondsSinceEpoch -
                dateFormattedB.millisecondsSinceEpoch) +
            (a.invoiceNumber - b.invoiceNumber);
        var descSortingCondition = (dateFormattedB.millisecondsSinceEpoch -
                dateFormattedA.millisecondsSinceEpoch) +
            (b.invoiceNumber - a.invoiceNumber);
        return sortingCondition.value == AppConstant.descending
            ? descSortingCondition
            : ascSortingCondition;
      });
    } else if (sortingOption.value == AppConstant.invoiceNumberSortingOption) {
      invoiceList.sort((a, b) {
        var ascSortingCondition = a.invoiceNumber - b.invoiceNumber;
        var descSortingCondition = b.invoiceNumber - a.invoiceNumber;
        return sortingCondition.value == AppConstant.descending
            ? descSortingCondition
            : ascSortingCondition;
      });
      invoiceSearchList.sort((a, b) {
        var ascSortingCondition = a.invoiceNumber - b.invoiceNumber;
        var descSortingCondition = b.invoiceNumber - a.invoiceNumber;
        return sortingCondition.value == AppConstant.descending
            ? descSortingCondition
            : ascSortingCondition;
      });
    }
    invoiceList.refresh();
    invoiceSearchList.refresh();
  }

  resetSortingParameters() {
    sortingOption.value = AppConstant.invoiceDateSortingOption;
    sortingCondition.value = AppConstant.descending;
  }

  getLatestInvoicesForDashboard() async {
    final DashboardController dashboardController =
        Get.put(DashboardController());
    invoiceScreensUserPermissions.value =
        authController.checkScreenUserPermission(AppConstant.invoicesScreen);
    List<InvoiceModel> invoices = [];
    resetSortingParameters();
    if (invoiceList.isEmpty || invoiceList.length < 5) {
      invoiceList.clear();
      String userId = CacheStorageService.instance.read(AppConstant.userId);
      String companyId =
          CacheStorageService.instance.read(AppConstant.companyId);
      var snapshot = await fireStore
          .collection(AppConstant.userMaster)
          .doc(userId)
          .collection(AppConstant.companyProfileMaster)
          .doc(companyId)
          .collection(AppConstant.invoiceMaster)
          .orderBy(AppConstant.invoiceDate, descending: true)
          .where(AppConstant.paymentStatus, isEqualTo: AppConstant.pending)
          .limit(5)
          .get();
      if (snapshot.docs.isNotEmpty) {
        for (var document in snapshot.docs) {
          var doc = document.data();
          doc[AppConstant.docId] = document.id;
          String name = doc[AppConstant.customerName];
          String email = doc[AppConstant.email];
          for (var customerElement in addCustomerController.customersData) {
            if (document.data()[AppConstant.customerId] ==
                customerElement.docId) {
              name = "${customerElement.firstName} ${customerElement.lastName}";
              email = customerElement.email;
            }
          }
          doc[AppConstant.customerName] = name;
          doc[AppConstant.email] = email;
          var invoiceModel = InvoiceModel.fromMap(
            data: doc,
            includePrices: true,
          );
          invoices.add(invoiceModel);
          invoiceList.add(invoiceModel);
        }
      }
    } else {
      invoiceList
          .where((invoice) => invoice.paymentStatus == AppConstant.pending)
          .take(5)
          .forEach((element) {
        invoices.add(InvoiceModel.fromMap(
          data: element.toMap(),
          includePrices: true,
        ));
      });
    }
    dashboardController.latestOpenInvoices.clear();
    dashboardController.latestOpenInvoices.addAll(invoices);
    dashboardController.latestOpenInvoices.sort((a, b) {
      var dateFormattedA = DateFormat("MM/dd/yyyy").parse(a.invoiceDate);
      var dateFormattedB = DateFormat("MM/dd/yyyy").parse(b.invoiceDate);
      var descSortingCondition = (dateFormattedA.millisecondsSinceEpoch -
              dateFormattedB.millisecondsSinceEpoch) +
          (a.invoiceNumber - b.invoiceNumber);
      return descSortingCondition;
    });
    dashboardController.latestOpenInvoices.refresh();
  }

  setInvoiceAcceptedPaymentMethods(String acceptedMethods) {
    currentInvoiceModel.value.invoiceAcceptedPaymentMethods = acceptedMethods;
  }

  setInvoicePaymentTerms(String paymentTerms) {
    currentInvoiceModel.value.invoicePaymentTerms = paymentTerms;
  }

  Future<Map<String, dynamic>> createRecurringInvoice() async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    String invoiceTotal = invoiceModel.total.toStringAsFixed(2);
    String currency =
        companyProfileController.companyInfo.value.currencyName.toLowerCase();
    String intervalName = invoiceModel.stripeSubscriptionIntervalName;
    int intervalCount = invoiceModel.stripeSubscriptionIntervalCount;
    String customerStripeId = invoiceModel.stripeCustomerId;
    String customerName = invoiceModel.customerName;
    String stripeAccountId = companyProfileController.stripeMerchantId.value;
    String invId = invoiceModel.docId;
    int recurringInvoiceStartTimestamp =
        invoiceModel.recurringInvoiceStartDateTimestamp;
    int recurringInvoiceEndTimestamp =
        invoiceModel.recurringInvoiceEndDateTimestamp;
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    Loader.showLoader();
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.createStripeRecurringInvoice,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable.call(<String, dynamic>{
        'amount': invoiceTotal,
        "currency": currency,
        "interval": intervalName,
        "interval_count": intervalCount,
        "customer_id": customerStripeId,
        "customer_name": customerName,
        "stripe_account_id": stripeAccountId,
        "user_id": userId,
        "company_id": companyId,
        "invoice_id": invId,
        "recurring_invoice_start_date_timestamp":
            recurringInvoiceStartTimestamp,
        "end_date": recurringInvoiceEndTimestamp,
      });
      log("response... ${jsonEncode(result.data)}");
      Loader.hideLoader();
      if (result.data["statusCode"] == 200) {
        return {
          AppConstant.stripeScheduleSubscriptionId: result.data["data"]
              ["stripe_schedule_subscription_id"],
          AppConstant.stripeActiveSubscriptionId: result.data["data"]
              ["stripe_active_subscription_id"],
          AppConstant.stripePriceId: result.data["data"]["stripe_price_id"],
        };
      } else {
        ShowSnackBar.error(result.data["message"]);
        return {};
      }
    } catch (e) {
      Loader.hideLoader();
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return {};
    }
  }

  Future<Map<String, dynamic>> updateRecurringInvoice() async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    String invId = invoiceModel.docId;
    String invoiceTotal = invoiceModel.total.toStringAsFixed(2);
    String currency =
        companyProfileController.companyInfo.value.currencyName.toLowerCase();
    String intervalName = invoiceModel.stripeSubscriptionIntervalName;
    int intervalCount = invoiceModel.stripeSubscriptionIntervalCount;
    String customerStripeId = invoiceModel.stripeCustomerId;
    String customerName = invoiceModel.customerName;
    String stripeAccountId = companyProfileController.stripeMerchantId.value;
    String stripeScheduleSubscriptionId =
        invoiceModel.stripeScheduleSubscriptionId;
    int recurringInvoiceStartTimestamp =
        invoiceModel.recurringInvoiceStartDateTimestamp;
    int recurringInvoiceEndTimestamp =
        invoiceModel.recurringInvoiceEndDateTimestamp;
    Loader.showLoader();
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.updateStripeRecurringInvoice,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable.call(<String, dynamic>{
        "user_id": userId,
        "company_id": companyId,
        "invoice_id": invId,
        'amount': invoiceTotal,
        "currency": currency,
        "interval": intervalName,
        "interval_count": intervalCount,
        "customer_id": customerStripeId,
        "customer_name": customerName,
        "stripe_account_id": stripeAccountId,
        "stripe_schedule_subscription_id": stripeScheduleSubscriptionId,
        "recurring_invoice_start_date_timestamp":
            recurringInvoiceStartTimestamp,
        "end_date": recurringInvoiceEndTimestamp,
      });

      log("response... ${jsonEncode(result.data)}");
      Loader.hideLoader();
      if (result.data["statusCode"] == 200) {
        return {
          AppConstant.stripeScheduleSubscriptionId: result.data["data"]
              ["subscription_id"],
          AppConstant.stripePriceId: result.data["data"]["price_id"],
        };
      } else {
        ShowSnackBar.error(result.data["message"]);
        return {};
      }
    } catch (e) {
      Loader.hideLoader();
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return {};
    }
  }

  Future<bool> cancelRecurringInvoice({
    required String stripeAccountId,
    required String subscriptionId,
  }) async {
    Loader.showLoader();
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.cancelStripeRecurringInvoice,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable.call(<String, dynamic>{
        "stripe_account_id": stripeAccountId,
        "subscription_id": subscriptionId,
      });

      log("response... ${jsonEncode(result.data)}");
      Loader.hideLoader();
      if (result.data["statusCode"] == 200) {
        return true;
      } else {
        ShowSnackBar.error(result.data["message"]);
        return false;
      }
    } catch (e) {
      Loader.hideLoader();
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return false;
    }
  }

  increaseInvoiceTotal({
    required List<InvoiceService> services,
    required double discountPercentage,
    required double taxPercentage,
    required bool isQuickInvoice,
    required double invoiceTotal,
  }) async {
    log("innnnnnnn");
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    final DashboardController dashboardController =
        Get.put(DashboardController());
    final now = DateTime.now();
    String docID = "${now.month}-${now.year}";
    if (now.month < 10) {
      docID = "0$docID";
    }

    // Update Invoice Totals Master
    dashboardController.yearlyTotalsModel.update(
      docID,
      (model) {
        model.ratios.paidInvoicesTotal += invoiceTotal;
        return model;
      },
      ifAbsent: () => TotalsModel.fromMap({
        AppConstant.ratios: {AppConstant.paidInvoicesTotal: invoiceTotal}
      }),
    );

    // Update Services Totals Master
    isQuickInvoice
        // ignore: avoid_function_literals_in_foreach_calls
        ? services.forEach((e) {
            double total = double.parse(e.total);
            dashboardController.yearlyTotalsModel.update(
              docID,
              (model) {
                model.quickInvoices.update(
                  e.serviceName,
                  (value) => value + total,
                  ifAbsent: () => total,
                );
                model.ratios.paidQuickInvoicesCount++;
                return model;
              },
              ifAbsent: () => TotalsModel.fromMap({
                AppConstant.quickInvoices: {e.serviceName: total},
                AppConstant.ratios: {
                  AppConstant.paidQuickInvoicesCount: 1,
                  AppConstant.paidInvoicesTotal: invoiceTotal
                }
              }),
            );
          })
        // ignore: avoid_function_literals_in_foreach_calls
        : services.forEach((e) {
            double total = double.parse(e.total);
            dashboardController.yearlyTotalsModel.update(
              docID,
              (model) {
                model.estimates.update(
                  e.serviceName,
                  (value) => value + total,
                  ifAbsent: () => total,
                );
                model.ratios.paidEstimatesCount++;
                return model;
              },
              ifAbsent: () => TotalsModel.fromMap({
                AppConstant.estimates: {
                  e.serviceName: total,
                },
                AppConstant.ratios: {
                  AppConstant.paidEstimatesCount: 1,
                }
              }),
            );
          });

    String fieldName =
        isQuickInvoice ? AppConstant.quickInvoices : AppConstant.estimates;
    await FirebaseFirestore.instance
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.totalsMaster)
        .doc(docID.toString())
        .set(
      {
        fieldName: isQuickInvoice
            ? dashboardController.yearlyTotalsModel[docID]?.quickInvoices ?? {}
            : dashboardController.yearlyTotalsModel[docID]?.estimates ?? {},
        AppConstant.ratios:
            dashboardController.yearlyTotalsModel[docID]?.ratios.toMap(),
      },
      SetOptions(merge: true),
    );
    getLatestInvoicesForDashboard();
  }

  decreaseInvoiceTotal({
    required List<InvoiceService> services,
    required double discountPercentage,
    required double taxPercentage,
    required bool isQuickInvoice,
    required String invoiceDate,
    required double invoiceTotal,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    final DashboardController dashboardController =
        Get.put(DashboardController());

    String docID =
        "${invoiceDate.split("/").first}-${invoiceDate.split("/").last}";

    dashboardController.yearlyTotalsModel.update(
      docID,
      (model) {
        if (model.ratios.paidInvoicesTotal < invoiceTotal) {
          model.ratios.paidInvoicesTotal = 0;
        } else {
          model.ratios.paidInvoicesTotal -= invoiceTotal;
        }
        return model;
      },
      ifAbsent: () => TotalsModel.fromMap({
        AppConstant.ratios: {AppConstant.paidInvoicesTotal: 0}
      }),
    );

    isQuickInvoice
        // ignore: avoid_function_literals_in_foreach_calls
        ? services.forEach(
            (e) => dashboardController.yearlyTotalsModel.update(
              docID,
              (model) {
                double total = double.parse(e.total);
                model.quickInvoices.update(
                  e.serviceName,
                  (value) => value == 0 || value < total ? 0 : value - total,
                  ifAbsent: () => 0,
                );
                if (model.ratios.paidQuickInvoicesCount > 0) {
                  model.ratios.paidQuickInvoicesCount--;
                }
                return model;
              },
              ifAbsent: () => TotalsModel.fromMap({
                AppConstant.quickInvoices: {e.serviceName: 0},
                AppConstant.ratios: {AppConstant.paidQuickInvoicesCount: 0}
              }),
            ),
          )
        // ignore: avoid_function_literals_in_foreach_calls
        : services.forEach(
            (e) => dashboardController.yearlyTotalsModel.update(
              docID,
              (model) {
                double total = double.parse(e.total);
                model.estimates.update(
                  e.serviceName,
                  (value) => value == 0 || value < total ? 0 : value - total,
                  ifAbsent: () => 0,
                );
                if (model.ratios.paidEstimatesCount > 0) {
                  model.ratios.paidEstimatesCount--;
                }
                return model;
              },
              ifAbsent: () => TotalsModel.fromMap({
                AppConstant.estimates: {e.serviceName: 0},
                AppConstant.ratios: {AppConstant.paidEstimatesCount: 0}
              }),
            ),
          );
    String fieldName =
        isQuickInvoice ? AppConstant.quickInvoices : AppConstant.estimates;
    await FirebaseFirestore.instance
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.totalsMaster)
        .doc(docID)
        .set(
      {
        fieldName: isQuickInvoice
            ? dashboardController.yearlyTotalsModel[docID]?.quickInvoices ?? {}
            : dashboardController.yearlyTotalsModel[docID]?.estimates ?? {},
        AppConstant.ratios:
            dashboardController.yearlyTotalsModel[docID]?.ratios.toMap(),
      },
      SetOptions(merge: true),
    );
  }

  getInvoiceById({
    required String invId,
    required bool setAsCurrentInvoice,
  }) async {
    bool viewPrices =
        checkInvoiceUserPermissions(permission: AppConstant.viewPrices) ||
            checkInvoiceUserPermissions(permission: AppConstant.editInvoices);
    if (setAsCurrentInvoice) {
      currentInvoiceModel.value = InvoiceModel.empty();
    }
    int index = invoiceList.indexWhere((element) => element.docId == invId);
    if (index != -1) {
      if (setAsCurrentInvoice) {
        currentInvoiceModel.value = InvoiceModel.fromMap(
          data: invoiceList[index].toMap(),
          includePrices: viewPrices,
        );
      }
    } else {
      String userId = CacheStorageService.instance.read(AppConstant.userId);
      String companyId =
          CacheStorageService.instance.read(AppConstant.companyId);
      var data = await fireStore
          .collection(AppConstant.userMaster)
          .doc(userId)
          .collection(AppConstant.companyProfileMaster)
          .doc(companyId)
          .collection(AppConstant.invoiceMaster)
          .doc(invId)
          .get();
      if (data.exists) {
        var doc = data.data()!;
        doc[AppConstant.docId] = data.id;
        var invModel = InvoiceModel.fromMap(
          data: doc,
          includePrices: viewPrices,
        );
        invoiceList.add(invModel);
        invoiceSearchList.add(invModel);
        if (setAsCurrentInvoice) {
          currentInvoiceModel.value = InvoiceModel.fromMap(
            data: doc,
            includePrices: viewPrices,
          );
        }
      }
    }
  }

  setInvoiceDataForPdfGeneration({
    required InvoiceModel invModel,
    required bool includePrices,
  }) async {
    currentInvoiceModel.value = InvoiceModel.fromMap(
      data: invModel.toMap(),
      includePrices: includePrices,
    );
  }

  setInvoiceDataForEdit({
    required InvoiceModel invModel,
    required CustomerModel customerModel,
  }) {
    currentInvoiceModel.value = InvoiceModel.fromMap(
      data: invModel.toMap(),
      includePrices: true,
    );
    currentCustomerModel.value = customerModel;
  }

  setInvoiceDataForEditEstimate({
    required String invoiceId,
    required EstimateModel estimateModel,
  }) async {
    int invIndex =
        invoiceList.indexWhere((element) => element.docId == invoiceId);
    if (invIndex == -1) {
      await getInvoiceById(
        invId: invoiceId,
        setAsCurrentInvoice: true,
      );
    } else {
      currentInvoiceModel.value = InvoiceModel.fromMap(
        data: invoiceList[invIndex].toMap(),
        includePrices: true,
      );
    }
    currentInvoiceEstimateModel = EstimateModel.fromMap(
      data: estimateModel.toMap(),
      includePrices: true,
    );
    currentCustomerModel.value = CustomerModel.empty();
    int customerIndex = addCustomerController.customersData.indexWhere(
        (element) => element.docId == currentInvoiceModel.value.customerId);
    if (customerIndex != -1) {
      currentCustomerModel.value = CustomerModel.fromMap(
          addCustomerController.customersData[customerIndex].toMap());
    }
  }

  setCustomerData(String name) {
    for (var customer in addCustomerController.customersData) {
      String fullName = "${customer.firstName} ${customer.lastName}";
      if (fullName == name) {
        currentCustomerModel.value = CustomerModel.fromMap(customer.toMap());
        currentInvoiceModel.value.customerId = customer.docId;
        currentInvoiceModel.value.customerName = fullName;
        for (var address in currentCustomerModel.value.customerAddressesList) {
          if (address.isPrimaryAddress) {
            currentInvoiceModel.value.address = address.formattedAddress;
            currentInvoiceModel.value.addressId = address.placeId;
            address.active = true;
          }
        }
        currentInvoiceModel.value.email = customer.email;
        currentInvoiceModel.value.customerPhone = customer.phoneNumber;
      }
    }
    currentInvoiceModel.refresh();
  }

  setPaidInvoiceFields({required int paidAtTimestamp}) {
    currentInvoiceModel.value.paymentStatus = AppConstant.paid;
    currentInvoiceModel.value.paidAt = paidAtTimestamp;
    currentInvoiceModel.value.updatedAt = paidAtTimestamp;
    currentInvoiceModel.value.paidAmount = currentInvoiceModel.value.total;
  }

  createInvoiceDoc() async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    var doc = fireStore
        .collection(AppConstant.userId)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .doc();
    currentInvoiceModel.value.docId = doc.id;
  }

  saveInvoiceData({
    required bool isEdit,
    required bool isEstimateInvoice,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    /* 
    String stripeConnectAccountId = workspaceDetailsController
        .workspaceModel.value.stripeData.stripeConnectAccountId; */
    int paidAtTimestamp = Timestamp.now().millisecondsSinceEpoch;
    var doc = fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .doc(currentInvoiceModel.value.docId);
    await uploadInvoiceDocuments(isEdit: isEdit);
    bool isPaid = currentInvoiceModel.value.paymentStatus == AppConstant.paid;
    if (isPaid) {
      setPaidInvoiceFields(paidAtTimestamp: paidAtTimestamp);
      if (currentInvoiceModel.value.isRecurring) {
        handlePaidRecurringInvoice(paidAtTimestamp: paidAtTimestamp);
      }
    }
    if (isEdit) {
      currentInvoiceModel.value.updatedAt =
          Timestamp.now().millisecondsSinceEpoch;
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      currentInvoiceModel.value.invoicePdfUrl = "";
      // Save Invoice Data to Firestore
      await doc.update(currentInvoiceModel.value.toMap());
    } else {
      currentInvoiceModel.value.createdAt =
          Timestamp.now().millisecondsSinceEpoch;
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      // Save Invoice Data to Firestore
      await doc.set(currentInvoiceModel.value.toMap());
      if (isEstimateInvoice) {
        estimatesController.addInvoiceIdToEstimate(
          estimateId: currentInvoiceEstimateModel.docId,
          invoiceId: doc.id,
        );
      }
      lastInvoiceNo = currentInvoiceModel.value.invoiceNumber;
    }
    var invoice = currentInvoiceModel.value;
    var customer = currentCustomerModel.value;
    if (isPaid) {
      if (isEstimateInvoice) {
        estimatesController.markEstimateAsPaid(
          estId: currentInvoiceModel.value.estimateId,
        );
      }
      increaseInvoiceTotal(
        services: invoice.serviceList,
        discountPercentage: invoice.discountPer,
        taxPercentage: invoice.taxRatePer,
        isQuickInvoice: !isEstimateInvoice,
        invoiceTotal: invoice.total,
      );
      emailAutomationController.addInvoicePaidEmail(
        modelId: invoice.docId,
        customerFirstName: customer.firstName,
        customerLastName: customer.lastName,
        customerName: invoice.customerName,
        customerId: invoice.customerId,
        customerEmail: invoice.email,
        invoicePaidTotal: invoice.total.toStringAsFixed(2),
        invoicePaidAt: paidAtTimestamp,
        customerPhone: invoice.customerPhone,
        serviceNamesList:
            invoice.serviceList.map((e) => e.serviceName).toList(),
      );
    }

    addPublicInvoiceData(
      invId: invoice.docId,
      customerPhone: invoice.customerPhone,
      customerPhoneCountryCode: customer.countryCode.toString(),
      customerEmail: invoice.email,
      customerCompanyName: customer.companyName,
      stripeLink: "",
      invoicePdfFileBytes: Uint8List(0),
      estimatePdfFileBytes: Uint8List(0),
      isQuickInvoice: !isEstimateInvoice,
    );
  }

  Future deleteInvoice({
    required String id,
    bool isQuick = true,
    bool deleteEstimate = true,
  }) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String companyId = CacheStorageService.instance.read(AppConstant.companyId);
    String estimateId = "";
    int invIndex = invoiceList.indexWhere((element) => element.docId == id);
    if (invIndex == -1) {
      await getInvoiceById(
        invId: id,
        setAsCurrentInvoice: false,
      );
      invIndex = invoiceList.indexWhere((element) => element.docId == id);
    }
    if (invIndex != -1) {
      InvoiceModel invoice = invoiceList[invIndex];

      if (invoice.docId == id) {
        for (var attachment in invoice.documents) {
          if (attachment.path.isNotEmpty) {
            await deletePhoto(attachment.path);
          }
        }
        estimateId = invoice.estimateId;
        if (invoice.recurrenceMainReferenceInvoiceDocId.isNotEmpty) {
          deleteRecurringInvoiceDataFromMainReference(
            recurringInvoiceId: id,
            recurringInvoiceStripeUrl: invoice.stripeInvoiceUrl,
            mainReferenceId: invoice.recurrenceMainReferenceInvoiceDocId,
          );
          if (invoice.paymentStatus == AppConstant.paid) {
            decreaseInvoiceTotal(
              services: invoice.serviceList,
              discountPercentage: invoice.discountPer,
              taxPercentage: invoice.taxRatePer,
              isQuickInvoice: estimateId.isEmpty,
              invoiceDate: invoice.invoiceDate,
              invoiceTotal: invoice.total,
            );
          }
        } else {
          if (invoice.isRecurring) {
            await deleteRecurringInvoiceDocuments(
              model: invoice,
              isQuickInvoice: estimateId.isEmpty,
            );
          } else {
            if (invoice.paymentStatus == AppConstant.paid) {
              decreaseInvoiceTotal(
                services: invoice.serviceList,
                discountPercentage: invoice.discountPer,
                taxPercentage: invoice.taxRatePer,
                isQuickInvoice: estimateId.isEmpty,
                invoiceDate: invoice.invoiceDate,
                invoiceTotal: invoice.total,
              );
            }
          }
          String stripeScheduleSubscriptionId =
              invoice.stripeScheduleSubscriptionId;
          int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          bool subscriptionIsOver =
              invoice.recurringInvoiceEndDateTimestamp < nowTimestamp;
          if (stripeScheduleSubscriptionId.isNotEmpty &&
              invoice.paymentStatus != AppConstant.paid &&
              !subscriptionIsOver) {
            await cancelRecurringInvoice(
              stripeAccountId: companyProfileController.stripeMerchantId.value,
              subscriptionId: stripeScheduleSubscriptionId,
            );
          }
        }
      }
    }
    await fireStore
        .collection(AppConstant.userMaster)
        .doc(userId)
        .collection(AppConstant.companyProfileMaster)
        .doc(companyId)
        .collection(AppConstant.invoiceMaster)
        .doc(id)
        .delete();
    invoiceList.removeWhere((element) => element.docId == id);
    invoiceSearchList.removeWhere((element) => element.docId == id);
    if (isQuick) {
      await fireStore.collection(AppConstant.publicInvoices).doc(id).delete();
    }
    Loader.hideLoader();
    if (!isQuick && estimateId.isNotEmpty && deleteEstimate) {
      await estimatesController.deleteEstimate(estimateId: estimateId);
    }
  }

  createInvoiceFromEstimate({
    required EstimateModel estimateModel,
    required CustomerModel customerModel,
    required bool isPaid,
  }) async {
    setInvoiceDataForCreateEstimate(
      estimateModel: estimateModel,
      customerModel: customerModel,
      calculateConvenienceFee: false,
    );
    if (isPaid) {
      setPaidInvoiceFields(
        paidAtTimestamp: Timestamp.now().millisecondsSinceEpoch,
      );
    }
    currentInvoiceModel.value.docId = estimateModel.docId;
    await saveInvoiceData(
      isEdit: false,
      isEstimateInvoice: true,
    );
    if (isPaid) {
      clearData();
    }
  }

  setInvoiceTotalsFromEstimate({
    required EstimateModel estimateModel,
    required bool calculateConvenienceFee,
  }) {
    // calculate convenience fee only if creating a new invoice from estimate at manage invoice details otherwise don't.
    if (calculateConvenienceFee) {
      double subtotalLessDiscount =
          estimateModel.subTotal - estimateModel.discountAmount;
      currentInvoiceModel.value.convenienceFeePercentage =
          companyProfileController.companyInfo.value.convenienceFeePercentage;
      currentInvoiceModel.value.convenienceFeeAmount = subtotalLessDiscount *
          (currentInvoiceModel.value.convenienceFeePercentage / 100);
      currentInvoiceModel.value.convenienceFeeAmount =
          currentInvoiceModel.value.convenienceFeeAmount.toPrecision(2);
    } else {
      currentInvoiceModel.value.convenienceFeeAmount = 0;
      currentInvoiceModel.value.convenienceFeePercentage = 0;
    }
    currentInvoiceModel.value.subTotal = estimateModel.subTotal;
    currentInvoiceModel.value.discountAmount = estimateModel.discountAmount;
    currentInvoiceModel.value.discountPer = estimateModel.discountPer;
    currentInvoiceModel.value.discountPercentageEnabled =
        estimateModel.discountPercentageEnabled;
    currentInvoiceModel.value.depositPercentageEnabled =
        estimateModel.depositPercentageEnabled;
    currentInvoiceModel.value.taxAmount = estimateModel.taxAmount;
    currentInvoiceModel.value.taxRatePer = estimateModel.taxPer;
    currentInvoiceModel.value.total =
        (estimateModel.total + currentInvoiceModel.value.convenienceFeeAmount)
            .toPrecision(2);
    currentInvoiceModel.value.depositAmount = estimateModel.depositAmount;
    currentInvoiceModel.value.depositPercentage =
        estimateModel.depositPercentage;
    currentInvoiceModel.value.isDepositPaid = estimateModel.isDepositPaid;
    currentInvoiceModel.value.depositPaidAt = estimateModel.depositPaidAt;
    currentInvoiceModel.refresh();
  }

  setCustomerDataFromEstimateModel({required EstimateModel estimateModel}) {
    currentInvoiceModel.value.customerId =
        currentInvoiceEstimateModel.customerId;
    currentInvoiceModel.value.customerName =
        currentInvoiceEstimateModel.customerName;
    currentInvoiceModel.value.address = currentInvoiceEstimateModel.address;
    currentInvoiceModel.value.addressId = currentInvoiceEstimateModel.addressId;
    currentInvoiceModel.value.email = currentInvoiceEstimateModel.customerEmail;
    currentInvoiceModel.value.customerPhone =
        currentInvoiceEstimateModel.customerPhone;
    currentInvoiceModel.refresh();
  }

  setInvoiceDataForCreateEstimate({
    required EstimateModel estimateModel,
    required CustomerModel customerModel,
    required bool calculateConvenienceFee,
  }) {
    currentInvoiceEstimateModel = EstimateModel.fromMap(
      data: estimateModel.toMap(),
      includePrices: true,
    );
    currentCustomerModel.value = CustomerModel.fromMap(customerModel.toMap());
    setCreateInvoiceDefaultData();
    setCustomerDataFromEstimateModel(estimateModel: estimateModel);
    currentInvoiceModel.value.serviceList = List.from(
      estimateModel.servicesList.map(
        (e) => InvoiceService(
          serviceId: e.serviceId,
          serviceName: e.serviceName,
          serviceDescription: e.serviceDescription,
          total: e.serviceTotal.toStringAsFixed(2),
          serviceImageUrl: e.image,
          customServiceImageUrl: e.customServiceImageUrl,
          lengthOfService: e.lengthOfService,
          onlineSelfSchedule: e.onlineSelfSchedule,
        ),
      ),
    );
    currentInvoiceModel.value.packagesList = List.from(
      estimateModel.packagesList.map(
        (e) => InvoicePackageModel.fromMap(
          data: e.toMap(),
          includePrices: true,
        ),
      ),
    );
    currentInvoiceModel.value.isDepositPaid = estimateModel.isDepositPaid;
    currentInvoiceModel.value.depositPaidAt = estimateModel.depositPaidAt;
    setInvoiceTotalsFromEstimate(
      estimateModel: estimateModel,
      calculateConvenienceFee: calculateConvenienceFee,
    );
  }

  setCreateInvoiceDefaultData() {
    var companyModel = companyProfileController.companyInfo.value;
    DateFormat dateFormat = DateFormat("MM/dd/yyyy");
    currentInvoiceModel.value.clear();
    currentInvoiceModel.value.invoiceNumber = lastInvoiceNo + 1;
    currentInvoiceModel.value.invoiceDate = dateFormat.format(DateTime.now());
    currentInvoiceModel.value.paymentTerm = "Due Upon Receipt";
    currentInvoiceModel.value.paymentStatus = AppConstant.pending;
    // setting estimate id and type here cause it's most suitable place and no other place sets it
    currentInvoiceModel.value.estimateId = currentInvoiceEstimateModel.docId;
    currentInvoiceModel.value.estimateType =
        currentInvoiceEstimateModel.estimateType;
    // setting tax and convenience fee here so if it's new quick invoice they set here and if it's from estimate they set in setInvoiceTotalsFromEstimate
    currentInvoiceModel.value.taxRatePer = companyModel.taxPercentage;
    currentInvoiceModel.value.convenienceFeePercentage =
        companyModel.convenienceFeePercentage;
  }

  String isValidRecurrenceData({
    required bool isRecurrenceStarted,
    required String recurrenceType,
    required String recurrenceStartDate,
    required String recurrenceEndDate,
  }) {
    String errorMessage = "";
    if (!isRecurrenceStarted && recurrenceStartDate.isEmpty) {
      errorMessage = "Please select recurrence start date";
      return errorMessage;
    }
    if (recurrenceEndDate.isEmpty) {
      errorMessage = "Please select recurrence end date";
      return errorMessage;
    }
    var dateFormat = DateFormat('MM/dd/yyyy');
    var startDate = dateFormat.parse(recurrenceStartDate);
    var endDate = dateFormat.parse(recurrenceEndDate);
    int differenceInDays = endDate.difference(startDate).inDays;
    if (differenceInDays < 7 && recurrenceType == AppConstant.weekly) {
      errorMessage =
          "Recurrence end date should be at least 7 days after start date";
      return errorMessage;
    } else if (differenceInDays < 14 &&
        recurrenceType == AppConstant.biWeekly) {
      errorMessage =
          "Recurrence end date should be at least 14 days after start date";
      return errorMessage;
    } else if (differenceInDays < 31 && recurrenceType == AppConstant.monthly) {
      errorMessage =
          "Recurrence end date should be at least 30 days after start date";
      return errorMessage;
    } else if (differenceInDays < 365 && recurrenceType == AppConstant.yearly) {
      errorMessage =
          "Recurrence end date should be at least 365 days after start date";
      return errorMessage;
    }
    return errorMessage;
  }

  Future<String> isValidStripeData() async {
    String errorMessage = "";
    String stripeId = companyProfileController.stripeMerchantId.value;
    if (stripeId.isEmpty) {
      errorMessage =
          "Please complete your bank information to create recurring invoices.";
      return errorMessage;
    }
    if (currentInvoiceModel.value.email.isEmpty) {
      errorMessage =
          "Please add email to customer in order to set up recurring invoices";
      return errorMessage;
    }
    if (currentCustomerModel.value.stripeConnectAccountCustomerId.isEmpty) {
      var stripeData =
          await addCustomerController.addCustomerToStripeConnectAccount(
        custId: currentCustomerModel.value.docId,
        isUpdate: true,
        customerName:
            "${currentCustomerModel.value.firstName} ${currentCustomerModel.value.lastName}",
        customerEmail: currentInvoiceModel.value.email,
        customerPhone: currentInvoiceModel.value.customerPhone,
        stripeMerchantId: stripeId,
      );
      if (stripeData.isNotEmpty) {
        currentCustomerModel.value.stripeConnectAccountCustomerId =
            stripeData["stripeCustomerId"];
        currentInvoiceModel.value.stripeCustomerId =
            stripeData["stripeCustomerId"];
      } else {
        errorMessage = "Failed to add client to stripe account";
        return errorMessage;
      }
    }
    return errorMessage;
  }

  setInvoiceRecurrenceDataForSave({
    required bool isRecurrenceStarted,
    required String recurrenceType,
    required String recurrenceStartDate,
    required String recurrenceEndDate,
  }) async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    invoiceModel.stripeCustomerId =
        currentCustomerModel.value.stripeConnectAccountCustomerId;
    var dateFormat = DateFormat('MM/dd/yyyy');
    var now = DateTime.now();
    if (!isRecurrenceStarted) {
      var formattedStartDate = dateFormat.parse(recurrenceStartDate);
      var startDate = DateTime(
        formattedStartDate.year,
        formattedStartDate.month,
        formattedStartDate.day,
        now.hour,
        now.minute,
        now.second,
      );
      invoiceModel.recurringInvoiceStartDateTimestamp =
          startDate.millisecondsSinceEpoch ~/ 1000;
    }
    var formattedEndDate = dateFormat.parse(recurrenceEndDate);
    var endDate = DateTime(
      formattedEndDate.year,
      formattedEndDate.month,
      formattedEndDate.day,
      now.hour + 1,
      now.minute,
      now.second,
    );
    invoiceModel.recurringInvoiceEndDateTimestamp =
        endDate.millisecondsSinceEpoch ~/ 1000;

    String formattedRecurrenceType = formatReccurenceTypeToIntervalName(
      recurrenceType.toLowerCase(),
    );
    if (formattedRecurrenceType == "biweek") {
      invoiceModel.stripeSubscriptionIntervalName = "week";
      invoiceModel.stripeSubscriptionIntervalCount = 2;
    } else {
      invoiceModel.stripeSubscriptionIntervalName = formattedRecurrenceType;
      invoiceModel.stripeSubscriptionIntervalCount = 1;
    }
    if (invoiceModel.stripeScheduleSubscriptionId.isEmpty) {
      var recurringInvoiceDataMap = await createRecurringInvoice();
      if (recurringInvoiceDataMap.isNotEmpty) {
        invoiceModel.stripeScheduleSubscriptionId =
            recurringInvoiceDataMap[AppConstant.stripeScheduleSubscriptionId];
        invoiceModel.stripeActiveSubscriptionId =
            recurringInvoiceDataMap[AppConstant.stripeActiveSubscriptionId];
        invoiceModel.stripePriceId =
            recurringInvoiceDataMap[AppConstant.stripePriceId];
      } else {
        clearInvoiceRecurrenceData();
        invoiceModel = currentInvoiceModel.value;
      }
    } else {
      var nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (nowTimestamp < invoiceModel.recurringInvoiceEndDateTimestamp) {
        var recurringInvoiceDataMap = await updateRecurringInvoice();
        if (recurringInvoiceDataMap.isNotEmpty) {
          invoiceModel.stripeScheduleSubscriptionId =
              recurringInvoiceDataMap[AppConstant.stripeScheduleSubscriptionId];
          invoiceModel.stripePriceId =
              recurringInvoiceDataMap[AppConstant.stripePriceId];
        }
      }
    }
    currentInvoiceModel.value = invoiceModel;
  }

  checkForCancelingRecurringInvoice({required bool isEditEnabled}) async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    bool subscriptionIsOver =
        invoiceModel.recurringInvoiceEndDateTimestamp < nowTimestamp;
    if (invoiceModel.stripeScheduleSubscriptionId.isNotEmpty &&
        isEditEnabled &&
        !subscriptionIsOver) {
      var canceled = await cancelRecurringInvoice(
        stripeAccountId: companyProfileController.stripeMerchantId.value,
        subscriptionId: invoiceModel.stripeScheduleSubscriptionId,
      );
      if (canceled) {
        clearInvoiceRecurrenceData();
      }
    }
  }

  clearInvoiceRecurrenceData() {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    invoiceModel.stripeScheduleSubscriptionId = "";
    invoiceModel.stripeActiveSubscriptionId = "";
    invoiceModel.stripePriceId = "";
    invoiceModel.stripeSubscriptionIntervalName = "";
    invoiceModel.stripeSubscriptionIntervalCount = 0;
    invoiceModel.recurringInvoiceStartDateTimestamp = 0;
    invoiceModel.recurringInvoiceEndDateTimestamp = 0;
    currentInvoiceModel.value = invoiceModel;
  }

  handlePaidRecurringInvoice({required int paidAtTimestamp}) async {
    if (currentInvoiceModel.value.recurrenceMainReferenceInvoiceDocId.isEmpty) {
      await markRecurringInvoiceDocumentsAsPaid(
        model: currentInvoiceModel.value,
        paidAtTimestamp: paidAtTimestamp,
        isQuickInvoice: currentInvoiceModel.value.estimateId.isEmpty,
      );
      for (var element in currentInvoiceModel.value.recurringInvoicesData) {
        element.paidAt = paidAtTimestamp;
      }
      String subscriptionId =
          currentInvoiceModel.value.stripeScheduleSubscriptionId;
      int nowTimestamp = DateTime.now().millisecondsSinceEpoch;
      bool subscriptionIsOver =
          currentInvoiceModel.value.recurringInvoiceEndDateTimestamp <
              nowTimestamp;
      if (subscriptionId.isNotEmpty && !subscriptionIsOver) {
        await cancelRecurringInvoice(
          stripeAccountId:
              estimatesController.companyFormController.stripeMerchantId.value,
          subscriptionId: subscriptionId,
        );
      }
    } else {
      await markRecurringInvoiceAsPaidInsideMainReferenceInvoice(
          currentInvoiceModel.value);
    }
  }

  uploadInvoiceDocuments({required bool isEdit}) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    if (isEdit) {
      int invoiceIndex = invoiceList.indexWhere(
          (element) => element.docId == currentInvoiceModel.value.docId);
      if (invoiceIndex != -1) {
        for (var document in invoiceList[invoiceIndex].documents) {
          bool exists = currentInvoiceModel.value.documents
              .where((element) => element.path == document.path)
              .isNotEmpty;
          if (!exists) {
            deletePhoto(document.path);
          }
        }
      }
    }
    for (int i = 0; i < currentInvoiceModel.value.documents.length; i++) {
      if (currentInvoiceModel.value.documents[i].bytes.isNotEmpty) {
        AttachmentModel attachmentModel =
            currentInvoiceModel.value.documents[i];
        Uint8List bytes = attachmentModel.bytes;
        String contentType = currentInvoiceModel.value.documents[i].mimeType;
        DateTime time = DateTime.now();
        Reference refer =
            firebaseStorage.ref(userId).child("Invoice").child(time.toString());
        await refer.putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
          ),
        );
        currentInvoiceModel.value.documents[i].url =
            await refer.getDownloadURL();
        currentInvoiceModel.value.documents[i].path = refer.fullPath;
        currentInvoiceModel.value.documents[i].bytes = Uint8List(0);
      }
    }
  }

  updateInvoiceTotals() {
    currentInvoiceModel.value.subTotal = 0;
    bool isService = currentInvoiceModel.value.serviceList.isNotEmpty;
    if (isService) {
      for (var element in currentInvoiceModel.value.serviceList) {
        currentInvoiceModel.value.subTotal +=
            double.tryParse(element.total) ?? 0;
      }
    } else {
      for (var element in currentInvoiceModel.value.packagesList) {
        currentInvoiceModel.value.subTotal += element.packageTotal;
      }
    }
    if (currentInvoiceModel.value.subTotal > 0) {
      if (currentInvoiceModel.value.discountPercentageEnabled) {
        currentInvoiceModel.value.discountAmount =
            ((currentInvoiceModel.value.subTotal *
                        currentInvoiceModel.value.discountPer) /
                    100)
                .toPrecision(2);
      } else {
        currentInvoiceModel.value.discountPer =
            ((currentInvoiceModel.value.discountAmount * 100) /
                    currentInvoiceModel.value.subTotal)
                .toPrecision(2);
      }
    } else {
      currentInvoiceModel.value.discountAmount = 0;
      currentInvoiceModel.value.discountPer = 0;
    }
    double lessDiscount = currentInvoiceModel.value.subTotal -
        currentInvoiceModel.value.discountAmount;
    currentInvoiceModel.value.taxAmount =
        ((lessDiscount * currentInvoiceModel.value.taxRatePer) / 100)
            .toPrecision(2);
    currentInvoiceModel.value.convenienceFeeAmount =
        ((lessDiscount * currentInvoiceModel.value.convenienceFeePercentage) /
                100)
            .toPrecision(2);
    currentInvoiceModel.value.total = (lessDiscount +
            currentInvoiceModel.value.taxAmount +
            currentInvoiceModel.value.convenienceFeeAmount)
        .toPrecision(2);
    if (currentInvoiceModel.value.total > 0) {
      if (currentInvoiceModel.value.depositPercentageEnabled &&
          !currentInvoiceModel.value.isDepositPaid) {
        currentInvoiceModel.value.depositAmount =
            ((currentInvoiceModel.value.total *
                        currentInvoiceModel.value.depositPercentage) /
                    100)
                .toPrecision(2);
      } else {
        currentInvoiceModel.value.depositPercentage =
            ((currentInvoiceModel.value.depositAmount * 100) /
                    currentInvoiceModel.value.total)
                .toPrecision(2);
      }
    }
    currentInvoiceModel.refresh();
  }

  markInvoiceAsPaid({
    required String invId,
    required bool isEstimateInvoice,
    required bool markEstimateAsPaid,
  }) async {
    int invIndex = invoiceList.indexWhere((element) => element.docId == invId);
    int paidAtTimestamp = Timestamp.now().millisecondsSinceEpoch;
    if (invIndex == -1) {
      await getInvoiceById(
        invId: invId,
        setAsCurrentInvoice: false,
      );
      invIndex = invoiceList.indexWhere((element) => element.docId == invId);
    }
    if (invIndex != -1) {
      currentInvoiceModel.value = InvoiceModel.fromMap(
        data: invoiceList[invIndex].toMap(),
        includePrices: true,
      );
      setPaidInvoiceFields(paidAtTimestamp: paidAtTimestamp);
      if (currentInvoiceModel.value.isRecurring) {
        handlePaidRecurringInvoice(paidAtTimestamp: paidAtTimestamp);
      }
      String userId = CacheStorageService.instance.read(AppConstant.userId);
      String companyId =
          CacheStorageService.instance.read(AppConstant.companyId);
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      currentInvoiceModel.value.invoicePdfUrl = "";
      await fireStore
          .collection(AppConstant.userMaster)
          .doc(userId)
          .collection(AppConstant.companyProfileMaster)
          .doc(companyId)
          .collection(AppConstant.invoiceMaster)
          .doc(currentInvoiceModel.value.docId)
          .update(currentInvoiceModel.value.toMap());
      if (isEstimateInvoice && markEstimateAsPaid) {
        estimatesController.markEstimateAsPaid(
          estId: currentInvoiceModel.value.estimateId,
        );
      }
      var model = currentInvoiceModel.value;
      var customerModel =
          await addCustomerController.getCustomerIdInfo(model.customerId);
      increaseInvoiceTotal(
        services: model.serviceList,
        discountPercentage: model.discountPer,
        taxPercentage: model.taxRatePer,
        isQuickInvoice: !isEstimateInvoice,
        invoiceTotal: model.total,
      );
      emailAutomationController.addInvoicePaidEmail(
        modelId: model.docId,
        customerFirstName: customerModel.firstName,
        customerLastName: customerModel.lastName,
        customerName: model.customerName,
        customerId: model.customerId,
        customerEmail: model.email,
        invoicePaidTotal: model.total.toStringAsFixed(2),
        invoicePaidAt: paidAtTimestamp,
        customerPhone: model.customerPhone,
        serviceNamesList: model.serviceList.map((e) => e.serviceName).toList(),
      );
      addPublicInvoiceData(
        invId: invId,
        customerPhone: model.customerPhone,
        customerPhoneCountryCode: customerModel.countryCode.toString(),
        customerEmail: model.email,
        customerCompanyName: customerModel.companyName,
        stripeLink: "",
        invoicePdfFileBytes: Uint8List(0),
        estimatePdfFileBytes: Uint8List(0),
        isQuickInvoice: !isEstimateInvoice,
      );
    }
  }

  clearData() {
    currentInvoiceModel.value.clear();
    currentInvoiceEstimateModel.clear();
    currentCustomerModel.value = CustomerModel.empty();
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
}
