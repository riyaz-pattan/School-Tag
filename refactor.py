import re

def refactor_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Add imports if not present
    if "import 'theme/app_theme.dart';" not in content:
        content = content.replace(
            "import 'package:flutter/material.dart';", 
            "import 'package:flutter/material.dart';\nimport 'theme/app_theme.dart';\nimport 'theme/glass_card.dart';"
        )

    # Color replacements (manual regex to avoid replacing colors in specific color combinations like text/buttons)
    replacements = [
        (r'const Color\(0xFFF4FAFF\)', 'AppTheme.surface'),
        (r'Color\(0xFFF4FAFF\)', 'AppTheme.surface'),
        
        (r'const Color\(0xFF00113A\)', 'AppTheme.primary'),
        (r'Color\(0xFF00113A\)', 'AppTheme.primary'),
        
        (r'const Color\(0xFF001F2A\)', 'AppTheme.onSurface'),
        (r'Color\(0xFF001F2A\)', 'AppTheme.onSurface'),
        
        (r'const Color\(0xFF757682\)', 'AppTheme.outline'),
        (r'Color\(0xFF757682\)', 'AppTheme.outline'),
        
        (r'const Color\(0xFFFFFFFF\)', 'AppTheme.surfaceContainerLowest'),
        (r'Color\(0xFFFFFFFF\)', 'AppTheme.surfaceContainerLowest'),
        (r'Colors\.white', 'AppTheme.onPrimary'),
        
        (r'const Color\(0xFFE6F6FF\)', 'AppTheme.surfaceContainerLow'),
        (r'Color\(0xFFE6F6FF\)', 'AppTheme.surfaceContainerLow'),
        
        (r'const Color\(0xFF399E9D\)', 'AppTheme.onTertiaryContainer'),
        (r'Color\(0xFF399E9D\)', 'AppTheme.onTertiaryContainer'),

        (r'const Color\(0xFFC5C6D2\)', 'AppTheme.outlineVariant'),
        (r'Color\(0xFFC5C6D2\)', 'AppTheme.outlineVariant'),
    ]

    for old, new in replacements:
        content = re.sub(old, new, content)

    # We shouldn't globally replace Container with GlassCard because Container is used for many small things.
    # We will just write the file with colors replaced to start.
    
    with open(filepath, 'w') as f:
        f.write(content)

if __name__ == '__main__':
    refactor_file('lib/super_admin_home_screen.dart')
