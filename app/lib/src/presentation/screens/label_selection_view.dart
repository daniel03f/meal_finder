import 'package:flutter/material.dart';
import 'package:meal_finder/src/presentation/screens/camera_inference_screen.dart';
import 'package:meal_finder/src/services/database_service.dart';

class LabelSelectionView extends StatefulWidget {

  const LabelSelectionView({
    super.key,
  });

  @override
  State<LabelSelectionView> createState() => _LabelSelectionViewState();
}

class _LabelSelectionViewState extends State<LabelSelectionView> {
  List<String> _allLabels = [];
  List<String> _filteredLabels = [];
  final List<String> _selectedLabels = [];
  final TextEditingController _searchController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLabels();
    _searchController.addListener(_filterLabels);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLabels() async {
    final labels =
        await _databaseService.getAllClasses();
    setState(() {
      _allLabels = labels;
      _filteredLabels = labels;
      _isLoading = false;
    });
  }

  void _filterLabels() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredLabels = _allLabels;
      } else {
        _filteredLabels = _allLabels
            .where((label) => label.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _toggleLabel(String label) {
    setState(() {
      if (_selectedLabels.contains(label)) {
        _selectedLabels.remove(label);
      } else {
        _selectedLabels.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select product to search'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search labels...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_selectedLabels.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedLabels.length,
                itemBuilder: (context, index) {
                  final label = _selectedLabels[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(label),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () => _toggleLabel(label),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredLabels.length,
                    itemBuilder: (context, index) {
                      final label = _filteredLabels[index];
                      final isSelected = _selectedLabels.contains(label);

                      return ListTile(
                        title: Text(label),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.radio_button_unchecked),
                        onTap: () => _toggleLabel(label),
                        selected: isSelected,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CameraInferenceScreen(selectedLabels: _selectedLabels, databaseService: _databaseService),
            ),
          );
        },
        icon: const Icon(Icons.search),
        label: Text('Start Searching (${_selectedLabels.length})'),
      ),
    );
  }
}
