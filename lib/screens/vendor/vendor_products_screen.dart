import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/currency_provider.dart';
import '../../services/api_service.dart';

class VendorProductsScreen extends StatefulWidget {
  const VendorProductsScreen({super.key});

  @override
  State<VendorProductsScreen> createState() => _VendorProductsScreenState();
}

class _VendorProductsScreenState extends State<VendorProductsScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';

  String get _currency => context.watch<CurrencyProvider>().currencySymbol;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vendor = context.read<VendorProvider>();
      final vid = vendor.vendorId;
      if (vid != null && vid > 0) {
        vendor.loadVendorProducts(vendorId: vid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Products',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.goldColor, size: 28),
            onPressed: () => _openAddEditProduct(),
          ),
        ],
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          var products = List<Map<String, dynamic>>.from(vendor.vendorProducts);

          if (_filterStatus != 'all') {
            products = products
                .where((p) => p['status']?.toString() == _filterStatus)
                .toList();
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            products = products
                .where((p) => p['name']?.toString().toLowerCase().contains(q) == true)
                .toList();
          }

          return Column(
            children: [
              _buildSearchAndFilter(vendor, products),
              Expanded(
                child: vendor.isLoadingProducts
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.goldColor))
                    : products.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppColors.goldColor,
                            onRefresh: () async {
                              final vid = vendor.vendorId;
                              if (vid != null && vid > 0) {
                                await vendor.loadVendorProducts(vendorId: vid);
                              }
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: products.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildProductCard(products[index], vendor),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchAndFilter(VendorProvider vendor, List<Map<String, dynamic>> products) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: AppColors.whiteColor,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    hintStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppColors.inkSoftColor, size: 20),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.creamColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'publish', child: Text('Published', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'draft', child: Text('Draft', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'pending', child: Text('Pending', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) => setState(() => _filterStatus = v ?? 'all'),
                    isDense: true,
                    style: const TextStyle(color: AppColors.inkColor, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (products.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${products.length} product${products.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
                const Spacer(),
                if (_filterStatus != 'all')
                  GestureDetector(
                    onTap: () => setState(() => _filterStatus = 'all'),
                    child: const Text('Clear filter',
                        style: TextStyle(color: AppColors.goldColor, fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, VendorProvider vendor) {
    final id = product['id'] as int;
    final status = product['status']?.toString() ?? 'draft';
    final stockStatus = product['stock_status']?.toString() ?? 'instock';
    final price = product['price']?.toString() ?? '0';
    final regularPrice = product['regular_price']?.toString();
    final salePrice = product['sale_price']?.toString();
    final images = product['images'] as List<dynamic>? ?? [];
    final imageUrl = images.isNotEmpty ? images[0]['src']?.toString() : null;
    final manageStock = product['manage_stock'] == true;
    final stockQtyRaw = product['stock_quantity']?.toString();
    final stockQty = manageStock && stockQtyRaw != null && stockQtyRaw.isNotEmpty
        ? stockQtyRaw
        : null;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'publish':
        statusColor = const Color(0xFF10B981);
        statusLabel = 'Published';
        break;
      case 'pending':
        statusColor = AppColors.goldColor;
        statusLabel = 'Pending';
        break;
      case 'draft':
        statusColor = AppColors.inkSoftColor;
        statusLabel = 'Draft';
        break;
      default:
        statusColor = AppColors.inkSoftColor;
        statusLabel = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProductDetailSheet(product),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 64,
                color: AppColors.indigoPaleColor,
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_outlined, color: AppColors.inkSoftColor))
                    : const Icon(Icons.image_outlined, color: AppColors.inkSoftColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name']?.toString() ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (salePrice != null && salePrice.isNotEmpty && salePrice != '0') ...[
                        Text('$_currency${double.tryParse(salePrice)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(
                                color: AppColors.coralColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Text('$_currency${double.tryParse(regularPrice ?? price)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(
                                color: AppColors.inkSoftColor,
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough)),
                      ] else ...[
                        Text('$_currency${double.tryParse(price)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(
                                color: AppColors.goldColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        stockStatus == 'instock' ? Icons.check_circle : Icons.error_outline,
                        color: stockStatus == 'instock'
                            ? const Color(0xFF10B981)
                            : AppColors.coralColor,
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                          stockStatus == 'instock'
                              ? (stockQty != null ? '$stockQty in stock' : 'In stock')
                              : 'Out of stock',
                          style: TextStyle(
                              color: stockStatus == 'instock'
                                  ? const Color(0xFF10B981)
                                  : AppColors.coralColor,
                              fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.inkSoftColor),
              onSelected: (action) {
                if (action == 'edit') {
                  _openAddEditProduct(product: product);
                } else if (action == 'publish') {
                  _quickUpdateStatus(id, 'publish', vendor);
                } else if (action == 'draft') {
                  _quickUpdateStatus(id, 'draft', vendor);
                } else if (action == 'delete') {
                  _confirmDelete(id, vendor);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit, color: AppColors.indigoColor, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ])),
                if (status != 'publish')
                  const PopupMenuItem(value: 'publish',
                      child: Row(children: [
                        Icon(Icons.publish, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 8),
                        Text('Publish'),
                      ])),
                if (status == 'publish')
                  const PopupMenuItem(value: 'draft',
                      child: Row(children: [
                        Icon(Icons.unpublished, color: AppColors.goldColor, size: 18),
                        SizedBox(width: 8),
                        Text('Unpublish'),
                      ])),
                const PopupMenuItem(value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: AppColors.coralColor, size: 18),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.coralColor)),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _quickUpdateStatus(int id, String newStatus, VendorProvider vendor) async {
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final ok = await _updateStatus(id, newStatus);
      if (mounted) {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(ok ? 'Status updated to $newStatus' : 'Failed to update status'),
          backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
          duration: const Duration(seconds: 2),
        ));
        if (ok) vendor.loadVendorProducts(vendorId: vendor.vendorId ?? 0);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status'),
              backgroundColor: AppColors.coralColor),
        );
      }
    }
  }

  Future<bool> _updateStatus(int id, String status) async {
    final api = context.read<VendorProvider>().apiService;
    return await api.updateProduct(id, {'status': status});
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No products yet',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Start adding products to your store',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _openAddEditProduct(),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add Product'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int id, VendorProvider vendor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Product',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to delete this product? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await vendor.deleteVendorProduct(id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Product deleted' : 'Failed to delete'),
                  backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coralColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showProductDetailSheet(Map<String, dynamic> product) {
    final images = product['images'] as List<dynamic>? ?? [];
    final categories = product['categories'] as List<dynamic>? ?? [];
    final tags = product['tags'] as List<dynamic>? ?? [];
    final status = product['status']?.toString() ?? 'draft';
    final price = product['price']?.toString() ?? '0';
    final regularPrice = product['regular_price']?.toString();
    final salePrice = product['sale_price']?.toString();
    final sku = product['sku']?.toString() ?? '-';
    final stockQty = product['stock_quantity']?.toString();
    final manageStock = product['manage_stock'] == true;
    final stockStatus = product['stock_status']?.toString() ?? 'instock';
    final type = product['type']?.toString() ?? 'simple';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: AppColors.creamColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inkSoftColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image gallery
                    if (images.isNotEmpty)
                      SizedBox(
                        height: 220,
                        child: PageView.builder(
                          itemCount: images.length,
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              images[i]['src']?.toString() ?? '',
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.indigoPaleColor,
                                child: const Icon(Icons.image_outlined,
                                    color: AppColors.inkSoftColor, size: 48),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: AppColors.indigoPaleColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Icon(Icons.image_outlined,
                              color: AppColors.inkSoftColor, size: 48),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Name & status
                    Row(
                      children: [
                        Expanded(
                          child: Text(product['name']?.toString() ?? 'Untitled',
                              style: const TextStyle(
                                  color: AppColors.inkColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Fraunces')),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'publish'
                                ? const Color(0xFF10B981).withOpacity(0.12)
                                : AppColors.goldColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(status.toUpperCase(),
                              style: TextStyle(
                                  color: status == 'publish'
                                      ? const Color(0xFF10B981)
                                      : AppColors.goldColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Price row
                    _buildDetailRow('Price', () {
                      if (salePrice != null && salePrice.isNotEmpty && salePrice != '0') {
                        return RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '$_currency${double.tryParse(salePrice)?.toStringAsFixed(2) ?? '0.00'}',
                                style: const TextStyle(
                                    color: AppColors.coralColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: '$_currency${double.tryParse(regularPrice ?? price)?.toStringAsFixed(2) ?? '0.00'}',
                                style: const TextStyle(
                                    color: AppColors.inkSoftColor,
                                    fontSize: 16,
                                    decoration: TextDecoration.lineThrough),
                              ),
                            ],
                          ),
                        );
                      }
                      return Text(
                          '$_currency${double.tryParse(price)?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                              color: AppColors.goldColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold));
                    }()),
                    const SizedBox(height: 16),

                    // Info cards
                    _buildInfoGrid([
                      {'label': 'SKU', 'value': sku},
                      {'label': 'Type', 'value': type[0].toUpperCase() + type.substring(1)},
                      {'label': 'Stock', 'value': manageStock ? (stockQty ?? '-') : stockStatus},
                      {'label': 'Status', 'value': status[0].toUpperCase() + status.substring(1)},
                    ]),
                    const SizedBox(height: 20),

                // Description
                Builder(builder: (_) {
                  final desc = product['description']?.toString();
                  final shortDesc = product['short_description']?.toString();
                  if ((desc != null && desc.isNotEmpty) || (shortDesc != null && shortDesc.isNotEmpty)) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Description',
                            style: TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Fraunces')),
                        const SizedBox(height: 8),
                        if (shortDesc != null && shortDesc.isNotEmpty)
                          Text(_stripHtml(shortDesc),
                              style: const TextStyle(
                                  color: AppColors.inkSoftColor, fontSize: 13, height: 1.5)),
                        if (desc != null && desc.isNotEmpty) ...[
                          if (shortDesc != null && shortDesc.isNotEmpty)
                            const SizedBox(height: 8),
                          Text(_stripHtml(desc),
                              style: const TextStyle(
                                  color: AppColors.inkColor, fontSize: 13, height: 1.5)),
                        ],
                        const SizedBox(height: 20),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }),

                    // Categories
                    if (categories.isNotEmpty) ...[
                      const Text('Categories',
                          style: TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Fraunces')),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: categories.map((c) {
                          final name = c is Map ? c['name']?.toString() ?? '' : c.toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.goldColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(name,
                                style: const TextStyle(
                                    color: AppColors.goldColor, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Tags
                    if (tags.isNotEmpty) ...[
                      const Text('Tags',
                          style: TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Fraunces')),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: tags.map((t) {
                          final name = t is Map ? t['name']?.toString() ?? '' : t.toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.whiteColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.sandColor),
                            ),
                            child: Text(name,
                                style: const TextStyle(
                                    color: AppColors.inkSoftColor, fontSize: 11)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openAddEditProduct(product: product);
                            },
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit Product'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.indigoColor,
                              side: const BorderSide(color: AppColors.indigoColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDelete(product['id'] as int,
                                  context.read<VendorProvider>());
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.coralColor,
                              foregroundColor: AppColors.whiteColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, Widget value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
        const SizedBox(height: 4),
        value,
      ],
    );
  }

  Widget _buildInfoGrid(List<Map<String, String>> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item['label']!,
                        style: const TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(item['value']!,
                        style: const TextStyle(
                            color: AppColors.inkColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  void _openAddEditProduct({Map<String, dynamic>? product}) {
    final vendorProvider = context.read<VendorProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VendorAddEditProductScreen(
          apiService: vendorProvider, // pass the provider to access its API service
          product: product,
          onSaved: () {
            vendorProvider.loadVendorProducts();
          },
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// ADD / EDIT PRODUCT SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class VendorAddEditProductScreen extends StatefulWidget {
  final dynamic apiService; // Can be VendorProvider (has ._api) or ApiService
  final Map<String, dynamic>? product;
  final VoidCallback? onSaved;

  const VendorAddEditProductScreen({
    super.key,
    required this.apiService,
    this.product,
    this.onSaved,
  });

  @override
  State<VendorAddEditProductScreen> createState() => _VendorAddEditProductScreenState();
}

class _VendorAddEditProductScreenState extends State<VendorAddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiService _api;
  bool _isSaving = false;
  bool _isEdit = false;

  String get _currency => context.watch<CurrencyProvider>().currencySymbol;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _shortDescCtrl = TextEditingController();
  final _regularPriceCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _stockQtyCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _dimLengthCtrl = TextEditingController();
  final _dimWidthCtrl = TextEditingController();
  final _dimHeightCtrl = TextEditingController();

  // State
  String _productType = 'simple';
  String _stockStatus = 'instock';
  bool _manageStock = false;
  String _taxStatus = 'taxable';
  String _catalogVisibility = 'visible';
  String _productStatus = 'publish';
  List<int> _categoryIds = [];
  List<int> _tagIds = [];

  // Image management
  List<_ProductImage> _images = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingImage = false;

  // Variation / attribute support
  List<_ProductAttribute> _attributes = [];
  List<Map<String, dynamic>> _variations = [];
  bool _loadingVariations = false;
  int? _activeAttributeIndex;
  List<Map<String, dynamic>> _globalAttributes = [];
  bool _loadingGlobalAttributes = false;
  final TextEditingController _optionValueCtrl = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _tags = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.product != null;
    // Resolve ApiService: if VendorProvider was passed, use its internal _api
    if (widget.apiService is ApiService) {
      _api = widget.apiService as ApiService;
    } else {
      // Try to access provider's internal api field, or fall back to shared instance
      try {
        _api = (widget.apiService as dynamic)._api as ApiService;
      } catch (_) {
        _api = context.read<VendorProvider>().apiService;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormData());
  }

  Future<void> _loadFormData() async {
    final cats = await _api.getProductCategories();
    final tags = await _api.getProductTags();
    if (mounted) {
      setState(() {
        _categories = cats;
        _tags = tags;
      });
    }

    if (widget.product != null) {
      final p = widget.product!;
      _nameCtrl.text = p['name']?.toString() ?? '';
      _descCtrl.text = p['description']?.toString() ?? '';
      _shortDescCtrl.text = p['short_description']?.toString() ?? '';
      _regularPriceCtrl.text = p['regular_price']?.toString() ?? '';
      _salePriceCtrl.text = p['sale_price']?.toString() ?? '';
      _skuCtrl.text = p['sku']?.toString() ?? '';
      _stockQtyCtrl.text = p['stock_quantity']?.toString() ?? '';
      _lowStockCtrl.text = p['low_stock_amount']?.toString() ?? '';
      _productType = p['type']?.toString() ?? 'simple';
      _stockStatus = p['stock_status']?.toString() ?? 'instock';
      _manageStock = p['manage_stock'] == true;
      _taxStatus = p['tax_status']?.toString() ?? 'taxable';
      _catalogVisibility = p['catalog_visibility']?.toString() ?? 'visible';
      _productStatus = p['status']?.toString() ?? 'publish';

      // Load existing images
      if (p['images'] is List) {
        _images = (p['images'] as List).map((img) {
          return _ProductImage(
            id: img['id'] as int?,
            url: img['src']?.toString() ?? '',
            isExisting: true,
          );
        }).toList();
      }

      if (p['categories'] is List) {
        _categoryIds = (p['categories'] as List)
            .map((c) => c is Map ? c['id'] as int : c as int)
            .toList();
      }
      if (p['tags'] is List) {
        _tagIds = (p['tags'] as List)
            .map((t) => t is Map ? t['id'] as int : t as int)
            .toList();
      }
      if (p['attributes'] is List) {
        _attributes = (p['attributes'] as List).map((a) {
          final options = (a['options'] as List?)?.map((o) => o.toString()).toList() ?? [];
          return _ProductAttribute(
            id: a['id'] as int?,
            name: a['name']?.toString() ?? '',
            options: options,
            visible: a['visible'] == true,
            variation: a['variation'] == true,
          );
        }).toList();
      }
      if (_productType == 'variable') {
        _loadVariations();
      }
      setState(() {});
    }
  }

  Future<void> _loadVariations() async {
    if (widget.product == null) return;
    final productId = widget.product!['id'] as int;
    setState(() => _loadingVariations = true);
    try {
      final vars = await _api.getProductVariations(productId);
      if (mounted) {
        setState(() {
          _variations = vars;
          _loadingVariations = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVariations = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _shortDescCtrl.dispose();
    _regularPriceCtrl.dispose();
    _salePriceCtrl.dispose();
    _skuCtrl.dispose();
    _stockQtyCtrl.dispose();
    _lowStockCtrl.dispose();
    _weightCtrl.dispose();
    _dimLengthCtrl.dispose();
    _dimWidthCtrl.dispose();
    _dimHeightCtrl.dispose();
    _optionValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _isUploadingImage = true);
        final uploaded = await _api.uploadProductImage(picked.path);
        if (mounted && uploaded != null) {
          setState(() {
            _images.add(_ProductImage(
              id: uploaded['id'] as int?,
              url: uploaded['source_url']?.toString() ?? uploaded['guid']?['raw']?.toString() ?? '',
              filePath: picked.path,
              isExisting: false,
            ));
            _isUploadingImage = false;
          });
        } else {
          setState(() => _isUploadingImage = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image upload failed. You can add image URLs manually.'),
                backgroundColor: AppColors.coralColor,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e'),
              backgroundColor: AppColors.coralColor),
        );
      }
    }
  }

  void _addImageUrl() {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Image URL'),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _images.add(_ProductImage(url: url, isExisting: false));
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate sale price < regular price
    if (_regularPriceCtrl.text.trim().isNotEmpty &&
        _salePriceCtrl.text.trim().isNotEmpty) {
      final regular = double.tryParse(_regularPriceCtrl.text.trim()) ?? 0;
      final sale = double.tryParse(_salePriceCtrl.text.trim()) ?? 0;
      if (sale >= regular) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale price must be less than regular price'),
            backgroundColor: AppColors.coralColor,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'type': _productType,
      'description': _descCtrl.text.trim(),
      'short_description': _shortDescCtrl.text.trim(),
      'regular_price': _regularPriceCtrl.text.trim(),
      'sale_price': _salePriceCtrl.text.trim().isEmpty ? '' : _salePriceCtrl.text.trim(),
      'sku': _skuCtrl.text.trim(),
      'manage_stock': _manageStock,
      'stock_status': _stockStatus,
      'tax_status': _taxStatus,
      'catalog_visibility': _catalogVisibility,
      'status': _productStatus,
      'categories': _categoryIds.map((id) => {'id': id}).toList(),
      'tags': _tagIds.map((id) => {'id': id}).toList(),
    };

    if (_manageStock && _stockQtyCtrl.text.isNotEmpty) {
      data['stock_quantity'] = int.tryParse(_stockQtyCtrl.text) ?? 0;
    }
    if (_lowStockCtrl.text.isNotEmpty) {
      data['low_stock_amount'] = int.tryParse(_lowStockCtrl.text);
    }

    // Images: existing by id, new by src
    final imageList = <Map<String, dynamic>>[];
    for (final img in _images) {
      if (img.isExisting && img.id != null) {
        imageList.add({'id': img.id});
      } else if (img.url.isNotEmpty) {
        imageList.add({'src': img.url});
      }
    }
    if (imageList.isNotEmpty) {
      data['images'] = imageList;
    }

    // Attributes for variable products
    if (_productType == 'variable' && _attributes.isNotEmpty) {
      data['attributes'] = _attributes.where((a) => a.name.isNotEmpty).map((a) {
        final attr = <String, dynamic>{
          'name': a.name,
          'visible': a.visible,
          'variation': a.variation,
          'options': a.options,
        };
        if (a.id != null) attr['id'] = a.id;
        return attr;
      }).toList();
    }

    try {
      if (_isEdit && widget.product != null) {
        final success = await _api.updateProduct(widget.product!['id'] as int, data);
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success ? 'Product updated!' : 'Failed to update product'),
            backgroundColor: success ? const Color(0xFF10B981) : AppColors.coralColor,
          ));
          if (success) {
            widget.onSaved?.call();
            Navigator.pop(context);
          }
        }
      } else {
        final result = await _api.createProduct(data);
        if (mounted) {
          setState(() => _isSaving = false);
          if (result != null && result['id'] != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Product created!'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
            if (_productType == 'variable' && _attributes.isNotEmpty) {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VendorAddEditProductScreen(
                    apiService: widget.apiService,
                    product: result,
                    onSaved: widget.onSaved,
                  ),
                ),
              );
            } else {
              widget.onSaved?.call();
              Navigator.pop(context);
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to create product'),
                backgroundColor: AppColors.coralColor,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.coralColor,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEdit ? 'Edit Product' : 'Add Product',
            style: const TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldColor))
                : const Text('Save',
                    style: TextStyle(
                        color: AppColors.goldColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Images'),
              const SizedBox(height: 12),
              _buildImageSection(),

              const SizedBox(height: 20),
              _buildSectionHeader('Basic Information'),
              const SizedBox(height: 12),
              _buildTextField(_nameCtrl, 'Product Name', required: true),
              const SizedBox(height: 10),
              _buildTextField(_descCtrl, 'Description', maxLines: 4),
              const SizedBox(height: 10),
              _buildTextField(_shortDescCtrl, 'Short Description', maxLines: 2),

              const SizedBox(height: 20),
              _buildSectionHeader('Pricing'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildTextField(_regularPriceCtrl, 'Regular Price ($_currency)', keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTextField(_salePriceCtrl, 'Sale Price ($_currency)', keyboardType: TextInputType.number)),
                ],
              ),

              const SizedBox(height: 20),
              _buildSectionHeader('Inventory'),
              const SizedBox(height: 12),
              _buildTextField(_skuCtrl, 'SKU'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      'Stock Status',
                      _stockStatus,
                      ['instock', 'outofstock', 'onbackorder'],
                      (v) => setState(() => _stockStatus = v ?? 'instock'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDropdown(
                      'Product Type',
                      _productType,
                      ['simple', 'variable'],
                      (v) => setState(() => _productType = v ?? 'simple'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manage Stock', style: TextStyle(fontSize: 13, color: AppColors.inkColor)),
                value: _manageStock,
                activeColor: AppColors.goldColor,
                onChanged: (v) => setState(() => _manageStock = v),
              ),
              if (_manageStock) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildTextField(_stockQtyCtrl, 'Stock Quantity', keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTextField(_lowStockCtrl, 'Low Stock Threshold', keyboardType: TextInputType.number)),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              _buildSectionHeader('Product Status'),
              const SizedBox(height: 12),
              _buildDropdown(
                'Status',
                _productStatus,
                ['publish', 'draft', 'pending'],
                (v) => setState(() => _productStatus = v ?? 'publish'),
              ),

              const SizedBox(height: 20),
              _buildSectionHeader('Categories & Tags'),
              const SizedBox(height: 12),
              _buildMultiSelectChips(
                'Categories',
                _categories,
                _categoryIds,
                (id) => setState(() {
                  if (_categoryIds.contains(id)) {
                    _categoryIds.remove(id);
                  } else {
                    _categoryIds.add(id);
                  }
                }),
              ),
              const SizedBox(height: 10),
              _buildMultiSelectChips(
                'Tags',
                _tags,
                _tagIds,
                (id) => setState(() {
                  if (_tagIds.contains(id)) {
                    _tagIds.remove(id);
                  } else {
                    _tagIds.add(id);
                  }
                }),
              ),
              const SizedBox(height: 20),

              // Attributes (for variable products)
              if (_productType == 'variable') ...[
                _buildSectionHeader('Attributes & Variations'),
                const SizedBox(height: 4),
                const Text(
                  'Define attributes like Size, Color, or Material. Each attribute can have multiple option values.',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
                ),
                const SizedBox(height: 14),
                ...List.generate(_attributes.length, (idx) {
                  return _buildAttributeEditor(idx, _attributes[idx]);
                }),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _attributes.add(_ProductAttribute())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Attribute', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.goldColor,
                          side: const BorderSide(color: AppColors.goldColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loadingGlobalAttributes ? null : _pickGlobalAttribute,
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: const Text('Use Existing', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.indigoColor,
                          side: const BorderSide(color: AppColors.indigoColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),

                // Variations
                if (_isEdit && widget.product != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('Generated Variations'),
                  const SizedBox(height: 12),
                  if (_loadingVariations)
                    const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
                  else if (_variations.isNotEmpty)
                    ..._buildVariationList()
                  else
                    _buildGenerateVariationsButton(),
                ],
                const SizedBox(height: 20),
              ],

              _buildSectionHeader('Settings'),
              const SizedBox(height: 12),
              _buildDropdown(
                'Tax Status',
                _taxStatus,
                ['taxable', 'shipping', 'none'],
                (v) => setState(() => _taxStatus = v ?? 'taxable'),
              ),
              const SizedBox(height: 10),
              _buildDropdown(
                'Catalog Visibility',
                _catalogVisibility,
                ['visible', 'catalog', 'search', 'hidden'],
                (v) => setState(() => _catalogVisibility = v ?? 'visible'),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.whiteColor))
                      : Text(_isEdit ? 'Update Product' : 'Create Product',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Image Section ───

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image preview grid
        if (_images.isNotEmpty) ...[
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final img = _images[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 100,
                        height: 100,
                        color: AppColors.indigoPaleColor,
                        child: img.filePath != null
                            ? Image.file(File(img.filePath!), fit: BoxFit.cover)
                            : img.url.isNotEmpty
                                ? Image.network(img.url, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image, color: AppColors.inkSoftColor))
                                : const Icon(Icons.image, color: AppColors.inkSoftColor),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(
                            color: AppColors.coralColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: AppColors.whiteColor),
                        ),
                      ),
                    ),
                    if (index == 0)
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.goldColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Featured',
                              style: TextStyle(color: AppColors.whiteColor, fontSize: 8)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Upload loading indicator
        if (_isUploadingImage) ...[
          const LinearProgressIndicator(color: AppColors.goldColor),
          const SizedBox(height: 8),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isUploadingImage ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.indigoColor,
                  side: const BorderSide(color: AppColors.indigoColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isUploadingImage ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Camera', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.indigoColor,
                  side: const BorderSide(color: AppColors.indigoColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addImageUrl,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('URL', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.indigoColor,
                  side: const BorderSide(color: AppColors.indigoColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Shared Widget Builders ───

  Widget _buildSectionHeader(String title) {
    return Text(title,
        style: const TextStyle(
            color: AppColors.inkColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Fraunces'));
  }

  Widget _buildTextField(TextEditingController ctrl, String label,
      {int maxLines = 1, TextInputType? keyboardType, bool required = false}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
        filled: true,
        fillColor: AppColors.whiteColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      style: const TextStyle(color: AppColors.inkColor, fontSize: 14),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options,
      void Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
          border: InputBorder.none,
          isDense: true,
        ),
        items: options.map((o) => DropdownMenuItem(
            value: o,
            child: Text(o[0].toUpperCase() + o.substring(1),
                style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
        style: const TextStyle(color: AppColors.inkColor, fontSize: 13),
      ),
    );
  }

  Widget _buildMultiSelectChips(String label, List<Map<String, dynamic>> items,
      List<int> selectedIds, void Function(int) onToggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.inkSoftColor, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.take(15).map((item) {
            final id = item['id'] as int;
            final name = item['name']?.toString() ?? '';
            final isSelected = selectedIds.contains(id);
            return GestureDetector(
              onTap: () => onToggle(id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.goldColor.withOpacity(0.15)
                      : AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected
                          ? AppColors.goldColor
                          : AppColors.sandColor),
                ),
                child: Text(name,
                    style: TextStyle(
                        color: isSelected ? AppColors.goldColor : AppColors.inkSoftColor,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Attribute Editor (enhanced) ───

  Widget _buildAttributeEditor(int index, _ProductAttribute attr) {
    final isActive = _activeAttributeIndex == index;
    final hasName = attr.name.trim().isNotEmpty;
    final hasOptions = attr.options.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasName ? AppColors.indigoColor.withOpacity(0.15) : AppColors.sandColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.indigoColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${index + 1}',
                      style: const TextStyle(
                        color: AppColors.indigoColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: attr.name,
                    onChanged: (v) => setState(() => _attributes[index].name = v),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkColor),
                    decoration: InputDecoration(
                      hintText: 'Attribute name (e.g. Color, Size, Material)',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor, fontWeight: FontWeight.normal),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      errorText: isActive && !hasName && attr.variation
                          ? 'Name is required for variations'
                          : null,
                      errorStyle: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                // Delete button
                GestureDetector(
                  onTap: () => _confirmRemoveAttribute(index),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.coralColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline, size: 16, color: AppColors.coralColor),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Toggle row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _buildToggleChip(
                  label: 'Used for variations',
                  value: attr.variation,
                  icon: Icons.layers_outlined,
                  onChanged: (v) => setState(() => _attributes[index].variation = v),
                ),
                _buildToggleChip(
                  label: 'Visible on product page',
                  value: attr.visible,
                  icon: Icons.visibility_outlined,
                  onChanged: (v) => setState(() => _attributes[index].visible = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(height: 1, color: AppColors.sandColor.withOpacity(0.5)),
          ),

          const SizedBox(height: 10),

          // Option values
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Values',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.inkSoftColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!hasOptions)
                      Text('(add at least one)',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.coralColor.withOpacity(0.7),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // Option chips
                if (hasOptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(attr.options.length, (oi) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.indigoColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.indigoColor.withOpacity(0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(attr.options[oi],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.indigoColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _attributes[index].options.removeAt(oi);
                                }),
                                child: Icon(Icons.close, size: 13,
                                  color: AppColors.coralColor.withOpacity(0.6)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      attr.variation
                          ? 'Add option values to generate variations'
                          : 'Add option values for this attribute',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.inkSoftColor.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // Add value button / inline form
                if (!isActive)
                  GestureDetector(
                    onTap: () => setState(() {
                      _optionValueCtrl.clear();
                      _activeAttributeIndex = index;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.goldColor.withOpacity(0.3),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 14, color: AppColors.goldColor),
                          SizedBox(width: 6),
                          Text('Add values',
                            style: TextStyle(fontSize: 11, color: AppColors.goldColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _buildAttributeInlineForm(index),
              ],
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool value,
    required IconData icon,
    required void Function(bool) onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value ? AppColors.goldColor.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? AppColors.goldColor.withOpacity(0.3) : AppColors.sandColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13,
              color: value ? AppColors.goldColor : AppColors.inkSoftColor),
            const SizedBox(width: 5),
            Text(label,
              style: TextStyle(
                fontSize: 11,
                color: value ? AppColors.goldColor : AppColors.inkSoftColor,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 3),
            Icon(value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 12,
              color: value ? AppColors.goldColor : AppColors.inkSoftColor.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveAttribute(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Attribute', style: TextStyle(fontWeight: FontWeight.w600)),
        content: Text('Remove "${_attributes[index].name.isNotEmpty ? _attributes[index].name : "this attribute"}" and its values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _attributes.removeAt(index));
              if (_activeAttributeIndex == index) _activeAttributeIndex = null;
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coralColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickGlobalAttribute() async {
    setState(() => _loadingGlobalAttributes = true);
    try {
      if (_globalAttributes.isEmpty) {
        _globalAttributes = await _api.getProductAttributes();
      }
    } catch (_) {
      _globalAttributes = [];
    }
    if (mounted) setState(() => _loadingGlobalAttributes = false);
    if (!mounted) return;

    if (_globalAttributes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No existing attributes found in your store admin.'),
          backgroundColor: AppColors.coralColor,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose an existing attribute',
                  style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Fraunces')),
            ),
            ..._globalAttributes.map((a) {
              final name = a['name']?.toString() ?? 'Attribute';
              return ListTile(
                leading: const Icon(Icons.checklist, color: AppColors.goldColor),
                title: Text(name),
                onTap: () => Navigator.pop(ctx, a),
              );
            }),
          ],
        );
      },
    );

    if (selected == null) return;

    final name = selected['name']?.toString() ?? '';
    final attrId = selected['id'] is int
        ? selected['id'] as int
        : int.tryParse(selected['id']?.toString() ?? '');
    if (name.isEmpty || attrId == null) return;

    // Load terms (values) for the selected attribute, then let the vendor
    // choose which values to include (instead of auto-adding all of them).
    List<String> allOptions = [];
    try {
      final terms = await _api.getProductAttributeTerms(attrId);
      allOptions = terms.map((t) => t['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } catch (_) {}

    if (!mounted) return;

    if (allOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This attribute has no values configured yet.'),
          backgroundColor: AppColors.coralColor,
        ),
      );
      return;
    }

    final chosen = <String>[];
    final chosenResult = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.whiteColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Choose values for "$name"',
                              style: const TextStyle(
                                  color: AppColors.inkColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Fraunces')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel',
                              style: TextStyle(color: AppColors.inkSoftColor)),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: allOptions.map((opt) {
                        final isSel = chosen.contains(opt);
                        return CheckboxListTile(
                          value: isSel,
                          activeColor: AppColors.goldColor,
                          title: Text(opt),
                          onChanged: (v) {
                            setSheet(() {
                              if (v == true) {
                                if (!chosen.contains(opt)) chosen.add(opt);
                              } else {
                                chosen.remove(opt);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.goldColor,
                          foregroundColor: AppColors.whiteColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Add selected values'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (chosenResult != true || chosen.isEmpty || !mounted) return;

    setState(() {
      _attributes.add(_ProductAttribute(
        id: attrId,
        name: name,
        options: List<String>.from(chosen),
        variation: true,
        visible: true,
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "$name" with ${chosen.length} values.'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Widget _buildAttributeInlineForm(int attrIndex) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.goldColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.goldColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _optionValueCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Red, Blue, Green  or  S | M | L',
                    hintStyle: TextStyle(fontSize: 11, color: AppColors.inkSoftColor),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: (v) => _addValuesToAttribute(attrIndex, v),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: () => _addValuesToAttribute(attrIndex, _optionValueCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  setState(() => _activeAttributeIndex = null);
                },
                child: const Icon(Icons.close, size: 18, color: AppColors.inkSoftColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Separate values with commas or pipes ( | )',
            style: TextStyle(color: AppColors.inkSoftColor.withOpacity(0.5), fontSize: 10)),
        ],
      ),
    );
  }

  void _addValuesToAttribute(int attrIndex, String raw) {
    final separator = raw.contains('|') ? '|' : ',';
    final values = raw
        .split(separator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (values.isNotEmpty) {
      setState(() {
        for (final v in values) {
          if (!_attributes[attrIndex].options.contains(v)) {
            _attributes[attrIndex].options.add(v);
          }
        }
        _activeAttributeIndex = null;
      });
    }
    _optionValueCtrl.clear();
  }

  // ─── Variations ───

  List<Widget> _buildVariationList() {
    return _variations.map((v) {
      final attrs = (v['attributes'] as List<dynamic>?) ?? [];
      final price = v['price']?.toString() ?? '0';
      final quantity = v['stock_quantity']?.toString() ?? '-';
      return Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.sandColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attrs.map((a) => a['option']?.toString() ?? '').join(' / '),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  Text(
                    '$_currency${double.tryParse(price)?.toStringAsFixed(2) ?? '0.00'}  |  Stock: $quantity',
                    style: const TextStyle(color: AppColors.goldColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: AppColors.goldColor),
              onPressed: () => _editVariationDialog(v),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGenerateVariationsButton() {
    return ElevatedButton.icon(
      onPressed: _generateVariations,
      icon: const Icon(Icons.auto_awesome, size: 18),
      label: const Text('Generate Variations from Attributes'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.goldColor,
        foregroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Future<void> _generateVariations() async {
    if (_attributes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one attribute first')),
      );
      return;
    }

    final productId = widget.product?['id'] as int?;
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the product first before generating variations')),
      );
      return;
    }

    final variationAttrs = _attributes.where((a) => a.variation && a.options.isNotEmpty).toList();
    if (variationAttrs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attributes marked "Used for variations" have options')),
      );
      return;
    }

    final combinations = _buildCombinations(variationAttrs);

    setState(() => _isSaving = true);
    try {
      for (final combo in combinations) {
        final varData = <String, dynamic>{
          'attributes': combo,
          'regular_price': _regularPriceCtrl.text.trim().isNotEmpty
              ? _regularPriceCtrl.text.trim()
              : '0',
          'manage_stock': true,
          'stock_quantity': _manageStock ? (int.tryParse(_stockQtyCtrl.text) ?? 10) : 10,
        };
        await _api.createProductVariation(productId, varData);
      }
      await _loadVariations();
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${combinations.length} variations generated!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.coralColor),
        );
      }
    }
  }

  List<List<Map<String, String>>> _buildCombinations(List<_ProductAttribute> attrs) {
    if (attrs.isEmpty) return [];
    if (attrs.length == 1) {
      return attrs[0].options.map((opt) => [
        {'name': attrs[0].name, 'option': opt},
      ]).toList();
    }
    final first = attrs[0];
    final rest = attrs.sublist(1);
    final restCombos = _buildCombinations(rest);
    final result = <List<Map<String, String>>>[];
    for (final opt in first.options) {
      for (final combo in restCombos) {
        result.add([
          {'name': first.name, 'option': opt},
          ...combo,
        ]);
      }
    }
    return result;
  }

  void _editVariationDialog(Map<String, dynamic> variation) {
    final priceCtrl = TextEditingController(text: variation['price']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: variation['stock_quantity']?.toString() ?? '');
    final enabled = variation['status']?.toString() == 'publish';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isEnabled = enabled;
          return AlertDialog(
            backgroundColor: AppColors.whiteColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Edit Variation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Price ($_currency)', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock Quantity', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled', style: TextStyle(fontSize: 13)),
                    value: isEnabled,
                    activeColor: AppColors.goldColor,
                    onChanged: (v) => setDialogState(() => isEnabled = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final productId = widget.product!['id'] as int;
                  final varId = variation['id'] as int;
                  final data = <String, dynamic>{
                    'price': priceCtrl.text.trim(),
                    'status': isEnabled ? 'publish' : 'private',
                  };
                  if (stockCtrl.text.trim().isNotEmpty) {
                    data['stock_quantity'] = int.tryParse(stockCtrl.text) ?? 0;
                    data['manage_stock'] = true;
                  }
                  Navigator.pop(ctx);
                  final ok = await _api.updateProductVariation(productId, varId, data);
                  if (ok && mounted) {
                    await _loadVariations();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Variation updated'),
                          backgroundColor: Color(0xFF10B981)),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save', style: TextStyle(color: AppColors.whiteColor)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductAttribute {
  int? id;
  String name;
  List<String> options;
  bool visible;
  bool variation;

  _ProductAttribute({
    this.id,
    this.name = '',
    this.options = const [],
    this.visible = true,
    this.variation = true,
  });
}

class _ProductImage {
  final int? id;
  final String url;
  final String? filePath;
  final bool isExisting;

  _ProductImage({
    this.id,
    this.url = '',
    this.filePath,
    this.isExisting = false,
  });
}