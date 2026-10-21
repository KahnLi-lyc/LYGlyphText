#if canImport(LYGlyphTextDemo)
    @testable import LYGlyphText
    @testable import LYGlyphTextDemo
    import UIKit
    import XCTest

    @MainActor
    final class HostListTests: XCTestCase {
        private let pixel: CGFloat = 0.5

        private func host(_ controller: UIViewController, width: CGFloat = 320) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            return window
        }

        private func tableCell(
            samples: HostMatrixSamples, content: HostMatrixContent, width: CGFloat
        ) -> HostMatrixTableCell {
            let cell = HostMatrixTableCell(style: .default, reuseIdentifier: "test")
            let row = samples.rows[0]
            cell.bind(row: row, content: content, state: HostMatrixRowState(rowID: row.id))
            cell.bounds = CGRect(x: 0, y: 0, width: width, height: 1)
            return cell
        }

        private func collectionCell(
            samples: HostMatrixSamples, content: HostMatrixContent, width: CGFloat
        ) -> HostMatrixCollectionCell {
            let cell = HostMatrixCollectionCell(frame: CGRect(x: 0, y: 0, width: width, height: 1))
            let row = samples.rows[0]
            cell.bind(row: row, content: content, state: HostMatrixRowState(rowID: row.id))
            return cell
        }

        private func fittingHeight(_ cell: UITableViewCell, width: CGFloat) -> CGFloat {
            cell.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }

        private func fittingHeight(_ cell: HostMatrixCollectionCell, width: CGFloat) -> CGFloat {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            attributes.size = CGSize(width: width, height: 80)
            return cell.preferredLayoutAttributesFitting(attributes).size.height
        }

        private func resize(_ window: UIWindow, controller: UIViewController, width: CGFloat) {
            window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }

        func testTableAutomaticRowsFitLongShortAndAttachmentSizeReplacements() throws {
            let samples = try HostMatrixSamples()
            let width: CGFloat = 320
            let heights = HostMatrixContent.allCases.reduce(into: [HostMatrixContent: CGFloat]()) { result, content in
                result[content] = fittingHeight(
                    tableCell(samples: samples, content: content, width: width),
                    width: width
                )
            }
            XCTAssertGreaterThan(heights[.longText] ?? 0, heights[.shortText] ?? .infinity)
            XCTAssertGreaterThan(heights[.largeImage] ?? 0, heights[.smallImage] ?? .infinity)
            XCTAssertGreaterThan(heights[.largeView] ?? 0, heights[.smallView] ?? .infinity)

            let controller = HostMatrixTableController(samples: samples, content: .shortText)
            let window = host(controller, width: width)
            defer { window.isHidden = true }
            XCTAssertEqual(controller.tableView.rowHeight, UITableView.automaticDimension)
            let shortHeight = controller.tableView.rectForRow(at: IndexPath(row: 0, section: 0)).height
            controller.setContent(.longText)
            controller.tableView.layoutIfNeeded()
            let longHeight = controller.tableView.rectForRow(at: IndexPath(row: 0, section: 0)).height
            XCTAssertGreaterThan(longHeight, shortHeight)
        }

        func testCollectionSelfSizingUsesAttributesWidthAndMatchesOffscreenMeasurement() throws {
            let samples = try HostMatrixSamples()
            let cell = collectionCell(samples: samples, content: .longText, width: 1)
            XCTAssertFalse(cell.statusLabel.text?.isEmpty ?? true)
            let statusHeight = cell.statusLabel.intrinsicContentSize.height
            XCTAssertTrue(statusHeight.isFinite)
            XCTAssertGreaterThan(statusHeight, 0)
            let scale = cell.traitCollection.displayScale > 0 ? cell.traitCollection.displayScale : 1
            for width in [CGFloat(240), 320, 600] {
                let fitted = fittingHeight(cell, width: width)
                let contentWidth = max(0, width - 2 * HostMatrixCollectionCell.horizontalInset)
                let expected = cell.glyphLabel.sizeThatFits(
                    CGSize(width: contentWidth, height: .infinity)
                ).height + statusHeight + 4 + 20
                XCTAssertEqual(fitted, ceil(expected * scale) / scale, accuracy: 1 / scale, "width \(width)")
                XCTAssertEqual(cell.glyphLabel.preferredMaxLayoutWidth, contentWidth)
            }
        }

        func testOfflineMeasurementAtZeroAndPositiveWidthNeverCallsFactory() throws {
            let samples = try HostMatrixSamples()
            let row = samples.rows[0]
            var factoryCalls = 0
            let provider = LYGlyphTextAttachmentViewProvider { _ in
                factoryCalls += 1
                return UIView(frame: CGRect(x: 0, y: 0, width: 999, height: 999))
            }
            let state = HostMatrixRowState(rowID: row.id)
            state.provider = provider
            let table = HostMatrixTableCell(style: .default, reuseIdentifier: "offline")
            table.bind(row: row, content: .largeView, state: state)
            let collection = HostMatrixCollectionCell(frame: .zero)
            collection.bind(row: row, content: .largeView, state: state)
            for width in [CGFloat(0), 320] {
                let tableHeight = fittingHeight(table, width: width)
                let collectionHeight = fittingHeight(collection, width: width)
                XCTAssertTrue(tableHeight.isFinite)
                XCTAssertTrue(collectionHeight.isFinite)
                if width > 0 {
                    XCTAssertGreaterThan(tableHeight, 0)
                    XCTAssertGreaterThan(collectionHeight, 0)
                }
            }
            XCTAssertEqual(factoryCalls, 0)
            XCTAssertNil(table.glyphLabel.descendantButton)
            XCTAssertNil(collection.glyphLabel.descendantButton)
        }

        func testTableAndCollectionNarrowWideNarrowBoundsReturnOriginalHeights() throws {
            let samples = try HostMatrixSamples()
            let widths = [CGFloat(0), 320, 600, 240, 320]
            let table = tableCell(samples: samples, content: .longText, width: 1)
            let collection = collectionCell(samples: samples, content: .longText, width: 1)
            let tableHeights = widths.map { fittingHeight(table, width: $0) }
            let collectionHeights = widths.map { fittingHeight(collection, width: $0) }
            XCTAssertEqual(tableHeights[1], tableHeights[4], accuracy: pixel)
            XCTAssertEqual(collectionHeights[1], collectionHeights[4], accuracy: pixel)
            XCTAssertGreaterThan(tableHeights[3], tableHeights[2])
            XCTAssertGreaterThan(collectionHeights[3], collectionHeights[2])

            let originalTableHeight = fittingHeight(table, width: 320)
            table.bounds.origin = CGPoint(x: 19, y: 23)
            collection.bounds.origin = CGPoint(x: 17, y: 29)
            XCTAssertEqual(fittingHeight(table, width: 320), originalTableHeight, accuracy: pixel)
            XCTAssertEqual(fittingHeight(collection, width: 320), collectionHeights[1], accuracy: pixel)
        }

        func testListReuseClearsPressedCallbackProviderAndMountedAttachmentState() throws {
            let samples = try HostMatrixSamples()
            let table = HostMatrixTableCell(style: .default, reuseIdentifier: "reuse")
            try exerciseReuse(
                samples: samples,
                hostView: table,
                label: table.glyphLabel,
                bind: table.bind,
                prepareForReuse: table.prepareForReuse,
                rowID: { table.rowID },
                eventCount: { table.eventCount }
            )
            let collection = HostMatrixCollectionCell(frame: .zero)
            try exerciseReuse(
                samples: samples,
                hostView: collection,
                label: collection.glyphLabel,
                bind: collection.bind,
                prepareForReuse: collection.prepareForReuse,
                rowID: { collection.rowID },
                eventCount: { collection.eventCount }
            )
        }

        func testRepeatedStableListLayoutConvergesWithoutOwningDelegateOrLayout() throws {
            let samples = try HostMatrixSamples()
            let tableController = HostMatrixTableController(samples: samples, content: .longText)
            let collectionController = HostMatrixCollectionController(samples: samples, content: .longText)
            let tableWindow = host(tableController, width: 0)
            let collectionWindow = host(collectionController, width: 0)
            defer {
                tableWindow.isHidden = true
                collectionWindow.isHidden = true
            }
            let tableDataSource = tableController.tableView.dataSource
            let tableDelegate = tableController.tableView.delegate
            let collectionDataSource = collectionController.collectionView.dataSource
            let collectionDelegate = collectionController.collectionView.delegate
            let collectionLayout = collectionController.collectionView.collectionViewLayout

            var firstTableHeight: CGFloat?
            var firstCollectionHeight: CGFloat?
            for width in [CGFloat(320), 600, 240, 320] {
                resize(tableWindow, controller: tableController, width: width)
                resize(collectionWindow, controller: collectionController, width: width)
                tableController.tableView.layoutIfNeeded()
                collectionController.collectionView.layoutIfNeeded()
                let labels = tableController.tableView.visibleCells.compactMap {
                    ($0 as? HostMatrixTableCell)?.glyphLabel
                } + collectionController.collectionView.visibleCells.compactMap {
                    ($0 as? HostMatrixCollectionCell)?.glyphLabel
                }
                XCTAssertFalse(labels.isEmpty)
                for label in labels {
                    XCTAssertGreaterThanOrEqual(label.bounds.width, 0)
                    XCTAssertLessThanOrEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, 2)
                }
                let before = labels.map(\.layoutMeasurementSnapshot)
                let invalidations = collectionController.layoutInvalidationCount
                for _ in 0 ..< 4 {
                    tableController.view.layoutIfNeeded()
                    collectionController.view.layoutIfNeeded()
                }
                XCTAssertEqual(labels.map(\.layoutMeasurementSnapshot), before)
                XCTAssertEqual(collectionController.layoutInvalidationCount, invalidations)

                let tableHeight = tableController.tableView.rectForRow(
                    at: IndexPath(row: 0, section: 0)
                ).height
                let collectionHeight = try XCTUnwrap(
                    collectionController.collectionView.layoutAttributesForItem(
                        at: IndexPath(item: 0, section: 0)
                    )
                ).size.height
                if width == 320, firstTableHeight == nil {
                    firstTableHeight = tableHeight
                    firstCollectionHeight = collectionHeight
                } else if width == 320 {
                    XCTAssertEqual(tableHeight, try XCTUnwrap(firstTableHeight), accuracy: pixel)
                    XCTAssertEqual(collectionHeight, try XCTUnwrap(firstCollectionHeight), accuracy: pixel)
                }
            }
            XCTAssertTrue(tableController.tableView.dataSource === tableDataSource)
            XCTAssertTrue(tableController.tableView.delegate === tableDelegate)
            XCTAssertTrue(collectionController.collectionView.dataSource === collectionDataSource)
            XCTAssertTrue(collectionController.collectionView.delegate === collectionDelegate)
            XCTAssertTrue(collectionController.collectionView.collectionViewLayout === collectionLayout)
            let finalLabels = tableController.tableView.visibleCells.compactMap {
                ($0 as? HostMatrixTableCell)?.glyphLabel
            } + collectionController.collectionView.visibleCells.compactMap {
                ($0 as? HostMatrixCollectionCell)?.glyphLabel
            }
            XCTAssertFalse(finalLabels.contains { $0 === tableDataSource as? AnyObject })
            XCTAssertFalse(finalLabels.contains { $0 === collectionLayout })
        }

        private func exerciseReuse(
            samples: HostMatrixSamples,
            hostView: UIView,
            label: LYGlyphTextLabel,
            bind: (HostMatrixRow, HostMatrixContent, HostMatrixRowState) -> Void,
            prepareForReuse: () -> Void,
            rowID: () -> Int?,
            eventCount: () -> Int
        ) throws {
            let firstRow = samples.rows[0]
            let secondRow = samples.rows[1]
            let firstState = HostMatrixRowState(rowID: firstRow.id)
            let secondState = HostMatrixRowState(rowID: secondRow.id)
            firstState.selectCallback(.b)
            let root = UIViewController()
            root.view.addSubview(hostView)
            hostView.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
            let window = host(root)
            defer { window.isHidden = true }

            bind(firstRow, .action, firstState)
            hostView.layoutIfNeeded()
            let layout = label.measuredLayout(width: label.bounds.width)
            let action = try XCTUnwrap(ActionGeometry(
                layout: layout,
                bounds: label.bounds,
                configuration: label.configuration
            ).entries.first)
            let point = try XCTUnwrap(action.rects.first).center
            XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
            XCTAssertNotNil(label.pressedActionIndex)

            bind(firstRow, .smallView, firstState)
            hostView.setNeedsLayout()
            hostView.layoutIfNeeded()
            let oldProvider = label.viewProvider
            let oldAttachment = label.descendantButton
            oldAttachment?.sendActions(for: .touchUpInside)
            XCTAssertEqual(firstState.buttonCount, 1)

            bind(secondRow, .action, secondState)
            XCTAssertNil(label.pressedActionIndex)
            XCTAssertEqual(rowID(), secondRow.id)
            XCTAssertEqual(eventCount(), 0)
            XCTAssertTrue(label.document === secondRow.documents[.action])
            XCTAssertFalse(label.viewProvider === oldProvider)
            XCTAssertNil(oldAttachment?.superview)
            XCTAssertEqual(secondState.buttonCount, 0)
            XCTAssertEqual(secondState.actionCount, 0)

            hostView.layoutIfNeeded()
            let currentLayout = label.measuredLayout(width: label.bounds.width)
            let currentAction = try XCTUnwrap(ActionGeometry(
                layout: currentLayout,
                bounds: label.bounds,
                configuration: label.configuration
            ).entries.first)
            let currentPoint = try XCTUnwrap(currentAction.rects.first).center
            XCTAssertTrue(label.beginActionInteraction(at: currentPoint, touchedView: label))
            label.endActionInteraction(at: currentPoint)
            XCTAssertEqual(firstState.actionCount, 0)
            XCTAssertEqual(secondState.actionCount, 1)
            XCTAssertEqual(eventCount(), 1)

            prepareForReuse()
            XCTAssertNil(rowID())
            XCTAssertEqual(eventCount(), 0)
            XCTAssertNil(label.document)
            XCTAssertNil(label.viewProvider)
            XCTAssertNil(label.onAction)
            XCTAssertNil(label.pressedActionIndex)
        }
    }

    private extension CGRect {
        var center: CGPoint {
            CGPoint(x: midX, y: midY)
        }
    }

    private extension UIView {
        var descendantButton: UIButton? {
            if let button = self as? UIButton { return button }
            return subviews.lazy.compactMap(\.descendantButton).first
        }
    }
#endif
