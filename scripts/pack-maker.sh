#!/bin/bash
# --- Maralva Pack-Maker v1.1 ---

# 1. Configuración de rutas y nombres
REPO_ROOT=$(dirname "$(readlink -f "$0")")/..
read -p "Nombre técnico del módulo (ej: conta_maralva): " MOD_NAME
read -p "Versión de Odoo (18 o 19): " VERSION

REPO_CUSTOM="/opt/odoo/$VERSION/gdigital-custom"
TARGET_DIR="$REPO_CUSTOM/$MOD_NAME"

if [ ! -d "$REPO_CUSTOM" ]; then
    echo "❌ Error: No se encuentra el repo en $REPO_CUSTOM"
    exit 1
fi

echo "--- Generando Pack: $MOD_NAME (Odoo $VERSION) ---"

# 2. Crear estructura estándar Maralva
mkdir -p "$TARGET_DIR"/{models,views,security,data,i18n,doc,static/description}
touch "$TARGET_DIR/__init__.py"
echo "from . import models" > "$TARGET_DIR/__init__.py"
touch "$TARGET_DIR/models/__init__.py"

# 3. Generar el README.md (Novedad)
cat > "$TARGET_DIR/README.md" <<EOF
# Maralva Pack - ${MOD_NAME//_/ }

## Descripción
Configuración y adaptaciones personalizadas por Maralva para la versión $VERSION de Odoo.

## Contenido
- Configuración de localización española (EUR/ES).
- Adaptaciones para VeriFactu y TicketBAI (según pack).
- Optimizaciones de Proyectos y Timesheets.

## Instalación
1. Asegúrate de tener las dependencias de la OCA en tu addons_path.
2. Instala el módulo desde el menú de aplicaciones de Odoo.

---
*Desarrollado por Maralva*
EOF

# 4. Manifiesto (__manifest__.py)
cat > "$TARGET_DIR/__manifest__.py" <<EOF
{
    'name': 'Maralva Pack - ${MOD_NAME//_/ }',
    'version': '$VERSION.0.1.0.0',
    'summary': 'Pack estándar Maralva para $VERSION',
    'category': 'Accounting/Localizations',
    'author': 'Maralva',
    'license': 'AGPL-3',
    'depends': [
        'base',
        'account',
        'l10n_es',
    ],
    'data': [
        'security/ir.model.access.csv',
        'data/res_company_data.xml',
    ],
    'installable': True,
    'auto_install': False,
    'application': True,
}
EOF

# 5. Configuración de País/Moneda (data/res_company_data.xml)
cat > "$TARGET_DIR/data/res_company_data.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="base.main_company" model="res.company">
            <field name="country_id" ref="base.es"/>
            <field name="currency_id" ref="base.EUR"/>
        </record>
    </data>
</odoo>
EOF

# 6. Seguridad (CSV con cabecera)
echo "id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink" > "$TARGET_DIR/security/ir.model.access.csv"

# 7. --- AUTOMATIZACIÓN GIT ---
echo "--- Sincronizando con Git local ---"
cd "$REPO_CUSTOM"
git add "$MOD_NAME"
git commit -m "[ADD] $MOD_NAME: Estructura base Maralva con README"

echo "✅ Pack $MOD_NAME creado con éxito en Odoo $VERSION."
echo "💡 Recuerda subir los cambios a GitHub desde tu PC o con tu script de push."