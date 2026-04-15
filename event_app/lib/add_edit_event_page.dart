import 'package:flutter/material.dart';
import 'models/event.dart';
import 'services/api_service.dart';

class AddEditEventPage extends StatefulWidget {
  final Event? event;

  const AddEditEventPage({super.key, this.event});

  @override
  State<AddEditEventPage> createState() => _AddEditEventPageState();
}

class _AddEditEventPageState extends State<AddEditEventPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController locationController;
  late TextEditingController priceController;
  late TextEditingController statusController;
  late TextEditingController dateController;
  late TextEditingController capacityController;
  late TextEditingController availableSeatsController;
  late TextEditingController categoryController;

  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(text: widget.event?.title ?? '');
    descriptionController = TextEditingController(text: widget.event?.description ?? '');
    locationController = TextEditingController(text: widget.event?.location ?? '');
    priceController = TextEditingController(text: widget.event?.price ?? '');
    statusController = TextEditingController(text: widget.event?.status ?? 'active');
    dateController = TextEditingController(
      text: widget.event?.eventDate.isNotEmpty == true
          ? widget.event!.eventDate.substring(0, 10)
          : '',
    );
    capacityController = TextEditingController(
      text: widget.event?.capacity.toString() ?? '0',
    );
    availableSeatsController = TextEditingController(
      text: widget.event?.availableSeats.toString() ?? '0',
    );
    categoryController = TextEditingController(text: widget.event?.category ?? '');
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    priceController.dispose();
    statusController.dispose();
    dateController.dispose();
    capacityController.dispose();
    availableSeatsController.dispose();
    categoryController.dispose();
    super.dispose();
  }

  Future<void> saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    final body = {
      "title": titleController.text.trim(),
      "description": descriptionController.text.trim(),
      "location": locationController.text.trim(),
      "price": double.tryParse(priceController.text.trim()) ?? 0,
      "status": statusController.text.trim(),
      "event_date": dateController.text.trim(),
      "capacity": int.tryParse(capacityController.text.trim()) ?? 0,
      "available_seats": int.tryParse(availableSeatsController.text.trim()) ?? 0,
      "category": categoryController.text.trim().isEmpty
          ? null
          : categoryController.text.trim(),
    };

    try {
      if (widget.event == null) {
        await ApiService.createEvent(body);
      } else {
        await ApiService.updateEvent(widget.event!.id, body);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return "$label boş bırakılamaz";
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.event != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Event" : "Add Event"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              buildTextField(controller: titleController, label: "Title"),
              buildTextField(controller: descriptionController, label: "Description"),
              buildTextField(controller: locationController, label: "Location"),
              buildTextField(
                controller: priceController,
                label: "Price",
                keyboardType: TextInputType.number,
              ),
              buildTextField(controller: statusController, label: "Status"),
              buildTextField(
                controller: dateController,
                label: "Event Date (YYYY-MM-DD)",
              ),
              buildTextField(
                controller: capacityController,
                label: "Capacity",
                keyboardType: TextInputType.number,
              ),
              buildTextField(
                controller: availableSeatsController,
                label: "Available Seats",
                keyboardType: TextInputType.number,
              ),
              buildTextField(controller: categoryController, label: "Category"),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: isLoading ? null : saveEvent,
                child: Text(isLoading ? "Saving..." : "Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}