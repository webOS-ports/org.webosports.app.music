/*
 * (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <QtCore/QCommandLineParser>
#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>

/*
 * Screenshots of every screen of the app, sized as on a device: luneos-
 * components' desktop stand-ins take the device's grid unit from
 * --profile=<device> (q25, mindphone, tp...), which qmltestrunner will not
 * pass through. screens.qml does the work; see tools/screenshots-host.sh.
 *
 *   musicapp-screens -I <import dir>... --out <dir> --profile=<device> screens.qml
 */
int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QCommandLineParser parser;
    QCommandLineOption imports(QStringLiteral("I"), QStringLiteral("QML import path"), QStringLiteral("dir"));
    QCommandLineOption out(QStringLiteral("out"), QStringLiteral("Where the screenshots go"), QStringLiteral("dir"));
    QCommandLineOption profile(QStringLiteral("profile"), QStringLiteral("Device profile (read by the stand-ins)"), QStringLiteral("name"));
    parser.addOptions({imports, out, profile});
    parser.addPositionalArgument(QStringLiteral("script"), QStringLiteral("screens.qml"));
    parser.process(app);
    if (parser.positionalArguments().isEmpty())
        parser.showHelp(1);

    QQmlApplicationEngine engine;
    for (const QString &dir : parser.values(imports))
        engine.addImportPath(dir);
    engine.rootContext()->setContextProperty(QStringLiteral("screensOut"), parser.value(out));
    engine.rootContext()->setContextProperty(QStringLiteral("screensProfile"), parser.value(profile));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, []() { QCoreApplication::exit(2); },
                     Qt::QueuedConnection);
    engine.load(parser.positionalArguments().constFirst());
    return app.exec();
}
