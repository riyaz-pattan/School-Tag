import re

with open('/Users/rameez/Desktop/student_app/lib/super_admin_home_screen.dart', 'r') as f:
    text = f.read()

# I prefer writing a completely updated version of the UI generation methods and replacing the giant block.
# Let's extract everything from `Widget _buildMobileTabletLayout()` down to the end of `Widget _buildInfoRow(...)` or `String _formatTime()`.
# Then we replace it with the new premium UI code.
